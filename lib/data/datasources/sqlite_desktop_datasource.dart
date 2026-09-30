import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:smart_doc_search/core/constants/app_constants.dart';
import 'package:smart_doc_search/core/utils/tag_page_calibrator.dart';
import 'package:smart_doc_search/data/datasources/koredb_datasource.dart';
import 'package:smart_doc_search/data/models/document_model.dart';
import 'package:smart_doc_search/features/search/search_query_parser.dart';

/// SQLite Desktop Data Source for Windows 11 and Linux
/// Provides ACID local storage using sqflite_common_ffi and shares
/// the exact same JSON backup/restore schema with Android KoreDB.
class SqliteDesktopDataSource implements KoreDbDataSource {
  final String? customDbPath;
  Database? _db;
  bool _initialized = false;

  SqliteDesktopDataSource({this.customDbPath});

  Future<Database> get database async {
    if (_db != null && _db!.isOpen) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
    }
  }

  Future<Database> _initDatabase() async {
    if (!_initialized) {
      if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
      }
      _initialized = true;
    }

    final String dbPath;
    if (customDbPath != null) {
      dbPath = customDbPath!;
    } else {
      final appDocDir = await getApplicationDocumentsDirectory();
      final dbFolder = Directory(p.join(appDocDir.path, 'SmartDocSearch', 'koredb_sqlite'));
      if (!await dbFolder.exists()) {
        await dbFolder.create(recursive: true);
      }
      dbPath = p.join(dbFolder.path, 'smart_doc_search.db');
    }

    final db = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 3,
        onConfigure: (db) async {
          // Desktop stability pragmas (Windows 11 & Linux).
          // WAL keeps reads fast while writes are in flight and busy_timeout
          // prevents transient 'database is locked' failures.
          try {
            await db.rawQuery('PRAGMA journal_mode = WAL;');
            await db.rawQuery('PRAGMA synchronous = NORMAL;');
            await db.rawQuery('PRAGMA busy_timeout = 5000;');
          } catch (_) {}
        },
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS documents (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              source_type TEXT NOT NULL,
              file_hash TEXT,
              file_path TEXT,
              page_count INTEGER,
              summary TEXT,
              chinese_summary TEXT,
              detected_language TEXT,
              tags_json TEXT,
              metadata_json TEXT,
              embedding_json TEXT,
              created_at INTEGER,
              updated_at INTEGER
            );
          ''');

          await db.execute('''
            CREATE TABLE IF NOT EXISTS pages (
              id TEXT PRIMARY KEY,
              document_id TEXT NOT NULL,
              page_number INTEGER NOT NULL,
              image_path TEXT,
              ocr_text TEXT,
              layout_blocks_json TEXT,
              embedding_json TEXT
            );
          ''');

          await db.execute('''
            CREATE TABLE IF NOT EXISTS tags (
              id TEXT PRIMARY KEY,
              name TEXT UNIQUE NOT NULL,
              category TEXT NOT NULL,
              aliases_json TEXT,
              usage_count INTEGER DEFAULT 0,
              code_system TEXT,
              created_at INTEGER,
              updated_at INTEGER
            );
          ''');

          await db.execute('CREATE INDEX IF NOT EXISTS idx_pages_doc ON pages (document_id);');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_tags_name ON tags (name);');

          await db.execute('''
            CREATE TABLE IF NOT EXISTS doc_index (
              doc_id TEXT PRIMARY KEY,
              body TEXT
            );
          ''');
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            try {
              await db.execute('ALTER TABLE tags ADD COLUMN code_system TEXT;');
            } catch (_) {}
          }
          if (oldVersion < 3) {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS doc_index (
                doc_id TEXT PRIMARY KEY,
                body TEXT
              );
            ''');
          }
        },
      ),
    );

    return db;
  }

  @override
  Future<String> insertDocument(Document doc) async {
    final db = await database;
    final tagsJson = json.encode(doc.tags.map((t) => t.toMap()).toList());
    final metaJson = json.encode(doc.metadata);
    final embJson = doc.embedding != null ? json.encode(doc.embedding) : null;
    final chSummary = (doc.metadata['chineseSummary'] ?? '').toString();

    await db.insert(
      'documents',
      {
        'id': doc.id,
        'title': doc.title,
        'source_type': doc.sourceType,
        'file_hash': doc.fileHash,
        'file_path': doc.filePath,
        'page_count': doc.pageCount,
        'summary': doc.summary,
        'chinese_summary': chSummary,
        'detected_language': doc.language,
        'tags_json': tagsJson,
        'metadata_json': metaJson,
        'embedding_json': embJson,
        'created_at': doc.createdAt,
        'updated_at': doc.updatedAt,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // Update tag definitions
    for (final tag in doc.tags) {
      final tid = tag.id.isNotEmpty ? tag.id : tag.name;
      final existing = await db.query('tags', where: 'name = ?', whereArgs: [tag.name], limit: 1);
      if (existing.isNotEmpty) {
        final currentCount = (existing.first['usage_count'] as num?)?.toInt() ?? 0;
        await db.update(
          'tags',
          {
            'usage_count': currentCount + 1,
            'updated_at': DateTime.now().millisecondsSinceEpoch,
            if (tag.codeSystem != null) 'code_system': tag.codeSystem,
          },
          where: 'name = ?',
          whereArgs: [tag.name],
        );
      } else {
        await db.insert(
          'tags',
          {
            'id': tid,
            'name': tag.name,
            'category': tag.category,
            'aliases_json': json.encode([]),
            'usage_count': 1,
            'code_system': tag.codeSystem,
            'created_at': DateTime.now().millisecondsSinceEpoch,
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }

    await _refreshDocIndexRow(doc.id, db);
    return doc.id;
  }

  @override
  Future<bool> updateDocument(Document doc) async {
    final db = await database;
    final tagsJson = json.encode(doc.tags.map((t) => t.toMap()).toList());
    final metaJson = json.encode(doc.metadata);
    final embJson = doc.embedding != null ? json.encode(doc.embedding) : null;
    final chSummary = (doc.metadata['chineseSummary'] ?? '').toString();

    final count = await db.update(
      'documents',
      {
        'title': doc.title,
        'source_type': doc.sourceType,
        'file_hash': doc.fileHash,
        'file_path': doc.filePath,
        'page_count': doc.pageCount,
        'summary': doc.summary,
        'chinese_summary': chSummary,
        'detected_language': doc.language,
        'tags_json': tagsJson,
        'metadata_json': metaJson,
        'embedding_json': embJson,
        'updated_at': doc.updatedAt,
      },
      where: 'id = ?',
      whereArgs: [doc.id],
    );
    if (count > 0) {
      await _refreshDocIndexRow(doc.id, db);
    }
    return count > 0;
  }

  @override
  Future<bool> deleteDocument(String id) async {
    final db = await database;
    await db.delete('pages', where: 'document_id = ?', whereArgs: [id]);
    await db.delete('doc_index', where: 'doc_id = ?', whereArgs: [id]);
    final count = await db.delete('documents', where: 'id = ?', whereArgs: [id]);
    _markIndexDirty(null);
    return count > 0;
  }

  @override
  Future<Document?> getDocument(String id) async {
    final db = await database;
    final rows = await db.query('documents', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return _mapRowToDocument(rows.first);
  }

  @override
  Future<List<Document>> getAllDocuments() async {
    final db = await database;
    final rows = await db.query('documents', orderBy: 'updated_at DESC');
    return rows.map(_mapRowToDocument).toList();
  }

  Document _mapRowToDocument(Map<String, dynamic> row) {
    List<TagItem> tags = [];
    if (row['tags_json'] != null) {
      try {
        final List list = json.decode(row['tags_json'] as String);
        tags = list.map((e) => TagItem.fromMap(Map<String, dynamic>.from(e))).toList();
      } catch (_) {}
    }

    Map<String, dynamic> meta = {};
    if (row['metadata_json'] != null) {
      try {
        meta = Map<String, dynamic>.from(json.decode(row['metadata_json'] as String));
      } catch (_) {}
    }

    List<double>? embedding;
    if (row['embedding_json'] != null) {
      try {
        final List list = json.decode(row['embedding_json'] as String);
        embedding = list.map((e) => (e as num).toDouble()).toList();
      } catch (_) {}
    }

    return Document(
      id: row['id'] as String,
      title: row['title'] as String,
      sourceType: (row['source_type'] ?? 'pdf') as String,
      fileHash: (row['file_hash'] ?? '') as String,
      filePath: (row['file_path'] ?? '') as String,
      pageCount: (row['page_count'] as num?)?.toInt() ?? 1,
      summary: (row['summary'] ?? '') as String,
      tags: tags,
      metadata: meta,
      language: (row['detected_language'] ?? 'zh-TW') as String,
      embedding: embedding,
      createdAt: (row['created_at'] as num?)?.toInt() ?? 0,
      updatedAt: (row['updated_at'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<List<Document>> queryByTags(List<String> tags, {String mode = 'AND'}) async {
    if (tags.isEmpty) return getAllDocuments();
    final all = await getAllDocuments();
    return all.where((doc) {
      final docTagNames = doc.tags.map((t) => t.name.toLowerCase()).toSet();
      if (mode == 'AND') {
        return tags.every((qt) => docTagNames.contains(qt.toLowerCase()));
      } else {
        return tags.any((qt) => docTagNames.contains(qt.toLowerCase()));
      }
    }).toList();
  }


  @override
  Future<SearchResult> hybridSearch({
    List<String> keywords = const [],
    List<String> tags = const [],
    String tagMode = 'AND',
    List<double>? semanticEmbedding,
    int limit = 20,
    int offset = 0,
  }) async {
    final sw = Stopwatch()..start();
    final keywordSet = EncodedKeywordSet.fromEncoded(keywords);
    final positiveKeywords = keywordSet.positive;

    // 1. Candidate documents (tags applied first so the heavy text scan only
    //    ever runs over the smallest possible set).
    var candidates = await _queryDocuments(includeEmbedding: semanticEmbedding != null);
    if (tags.isNotEmpty) {
      candidates = candidates.where((doc) {
        final docTagNames = doc.tags.map((t) => t.name.toLowerCase()).toSet();
        if (tagMode == 'AND') {
          return tags.every((qt) => docTagNames.contains(qt.toLowerCase()));
        }
        return tags.any((qt) => docTagNames.contains(qt.toLowerCase()));
      }).toList();
    }

    // 2. Keyword scan over the maintained lower-cased full-text cache.
    await _ensureDocIndex();
    final bodies = await _loadIndexBodies(candidates.map((d) => d.id).toList());

    final bool constrainByText = positiveKeywords.isNotEmpty || keywordSet.excluded.isNotEmpty;
    final bool exclusionOnly = positiveKeywords.isEmpty &&
        keywordSet.excluded.isNotEmpty &&
        semanticEmbedding == null &&
        tags.isEmpty;
    final bool noQuery = !constrainByText && semanticEmbedding == null && tags.isEmpty;

    final scored = <DocumentHit>[];
    for (final doc in candidates) {
      final body = bodies[doc.id] ?? ('${doc.title} ${doc.summary}').toLowerCase();

      // AND (+) / NOT (-) operator gates.
      if (constrainByText && !keywordSet.matchesGates(body)) continue;

      double kwScore = 0.0;
      if (positiveKeywords.isNotEmpty) {
        kwScore = _termScore(body, positiveKeywords);
        if (kwScore <= 0 && semanticEmbedding == null && tags.isEmpty) continue;
      }

      double vecScore = 0.0;
      if (semanticEmbedding != null && doc.embedding != null) {
        vecScore = _cosineSimilarity(semanticEmbedding, doc.embedding!);
      }

      double tagScore = 0.0;
      final matchedTags = <String>[];
      if (tags.isNotEmpty) {
        final docTagNames = doc.tags.map((t) => t.name.toLowerCase()).toSet();
        for (final t in tags) {
          if (docTagNames.contains(t.toLowerCase())) matchedTags.add(t);
        }
        tagScore = matchedTags.length / tags.length;
      }

      final double totalScore = (noQuery || exclusionOnly)
          ? 1.0
          : (AppConstants.weightKeyword * kwScore) +
              (AppConstants.weightVector * vecScore) +
              (AppConstants.weightTag * tagScore);

      if (!noQuery && !exclusionOnly && totalScore <= 0) continue;

      scored.add(DocumentHit(
        document: doc,
        score: totalScore,
        matchedTags: matchedTags,
      ));
    }

    // 3. Rank and slice before the expensive per-document page work.
    scored.sort((a, b) => b.score.compareTo(a.score));
    final total = scored.length;
    final paged = scored.skip(offset).take(limit).toList();

    // 4. Snippet + calibrated page number only for the returned window.
    final enriched = await _enrichHits(paged, positiveKeywords, tags);

    sw.stop();
    return SearchResult(
      items: enriched,
      total: total,
      tookMs: sw.elapsedMilliseconds,
    );
  }

  /// Loads documents for search. Vector JSON is only decoded when semantic
  /// search is active, avoiding the cost of parsing megabytes of embedding data
  /// on every keyword-only query (a major win on large corpora).
  Future<List<Document>> _queryDocuments({bool includeEmbedding = false}) async {
    final db = await database;
    final rows = await db.query(
      'documents',
      columns: includeEmbedding
          ? null
          : const [
              'id',
              'title',
              'source_type',
              'file_hash',
              'file_path',
              'page_count',
              'summary',
              'chinese_summary',
              'detected_language',
              'tags_json',
              'metadata_json',
              'created_at',
              'updated_at',
            ],
      orderBy: 'updated_at DESC',
    );
    return rows.map(_mapRowToDocument).toList();
  }

  /// Attaches the highlight snippet and calibrated page number to the hits that
  /// are actually returned, loading page text only for those documents.
  Future<List<DocumentHit>> _enrichHits(
    List<DocumentHit> hits,
    List<String> keywords,
    List<String> tags,
  ) async {
    if (hits.isEmpty) return hits;
    final pagesByDoc = await _loadPageMap(hits.map((h) => h.document.id).toList());

    final out = <DocumentHit>[];
    for (final hit in hits) {
      final doc = hit.document;
      final pages = pagesByDoc[doc.id] ?? const <PageItem>[];
      int? pageNumber;
      String? snippet;

      if (pages.isNotEmpty) {
        pageNumber = TagPageCalibrator.resolveSubstantivePageForSearchHit(
          searchKeywords: keywords,
          searchTags: tags,
          docTags: doc.tags,
          docPages: pages,
          docSummary: doc.summary,
        );
        if (keywords.isNotEmpty) {
          final targetPage = pages.firstWhere(
            (p) => p.pageNumber == pageNumber,
            orElse: () => pages.first,
          );
          snippet = _snippetFromText(targetPage.ocrText, keywords) ??
              _snippetFromText('${doc.title} ${doc.summary}', keywords);
        }
      }
      if (snippet == null && keywords.isNotEmpty) {
        snippet = _snippetFromText('${doc.title} ${doc.summary}', keywords);
      }

      out.add(DocumentHit(
        document: doc,
        score: hit.score,
        highlight: snippet,
        matchedTags: hit.matchedTags,
        pageNumber: pageNumber,
      ));
    }
    return out;
  }

  /// Bulk page loading restricted to the given documents (chunked to stay well
  /// below SQLite's bound-parameter limit).
  Future<Map<String, List<PageItem>>> _loadPageMap(List<String> docIds) async {
    final db = await database;
    final map = <String, List<PageItem>>{};
    if (docIds.isEmpty) return map;
    const chunkSize = 400;
    for (var i = 0; i < docIds.length; i += chunkSize) {
      final end = (i + chunkSize < docIds.length) ? i + chunkSize : docIds.length;
      final slice = docIds.sublist(i, end);
      if (slice.isEmpty) continue;
      final placeholders = List.filled(slice.length, '?').join(',');
      final rows = await db.rawQuery(
        'SELECT * FROM pages WHERE document_id IN ($placeholders) ORDER BY page_number ASC',
        slice,
      );
      for (final row in rows) {
        map.putIfAbsent(row['document_id'] as String, () => []).add(_mapRowToPage(row));
      }
    }
    return map;
  }

  static String? _snippetFromText(String text, List<String> keywords) {
    if (text.isEmpty) return null;
    final lower = text.toLowerCase();
    for (final rawKeyword in keywords) {
      final keyword = rawKeyword.toLowerCase().trim();
      if (keyword.isEmpty) continue;
      final index = lower.indexOf(keyword);
      if (index != -1) {
        final start = max(0, index - 50);
        final end = min(text.length, index + keyword.length + 50);
        return '...${text.substring(start, end).trim()}...';
      }
    }
    return null;
  }

  /// Counts keyword occurrences with plain substring scanning instead of
  /// compiling a RegExp per keyword per page (substantially faster).
  static double _termScore(String haystackLower, List<String> terms) {
    if (terms.isEmpty || haystackLower.isEmpty) return 0.0;
    var score = 0.0;
    for (final rawTerm in terms) {
      final term = rawTerm.toLowerCase().trim();
      if (term.isEmpty) continue;
      var count = 0;
      var index = 0;
      while (true) {
        final found = haystackLower.indexOf(term, index);
        if (found < 0) break;
        count++;
        index = found + term.length;
        if (count >= 64) break;
      }
      if (count > 0) {
        score += count * 1.5 / (count + 1.0);
      }
    }
    return score;
  }

  // ---------------------------------------------------------------------------
  // Full-text cache (doc_index) keeping keyword search fast on large corpora.
  // Every write path keeps the cache consistent and a document/index count check
  // acts as a safety net, rebuilding transparently if the cache ever drifts.
  // ---------------------------------------------------------------------------

  bool _indexReady = false;
  final Set<String> _dirtyDocIds = <String>{};

  void _markIndexDirty(String? docId) {
    if (docId != null && docId.isNotEmpty) _dirtyDocIds.add(docId);
    _indexReady = false;
  }

  Future<void> _refreshDocIndexRow(String docId, [Database? dbOverride]) async {
    final db = dbOverride ?? await database;
    final docRows = await db.query(
      'documents',
      columns: ['title', 'summary'],
      where: 'id = ?',
      whereArgs: [docId],
      limit: 1,
    );
    if (docRows.isEmpty) {
      await db.delete('doc_index', where: 'doc_id = ?', whereArgs: [docId]);
      _dirtyDocIds.remove(docId);
      return;
    }
    final pageRows = await db.query(
      'pages',
      columns: ['ocr_text'],
      where: 'document_id = ?',
      whereArgs: [docId],
      orderBy: 'page_number ASC',
    );
    final body = StringBuffer()
      ..write(docRows.first['title'] ?? '')
      ..write(' ')
      ..write(docRows.first['summary'] ?? '')
      ..write(' ');
    for (final row in pageRows) {
      body.write((row['ocr_text'] ?? '') as String);
      body.write(' ');
    }
    await db.insert(
      'doc_index',
      {'doc_id': docId, 'body': body.toString().toLowerCase()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _dirtyDocIds.remove(docId);
  }

  Future<void> _rebuildDocIndex() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('doc_index');
      final docs = await txn.query('documents', columns: ['id', 'title', 'summary']);
      final pages = await txn.query(
        'pages',
        columns: ['document_id', 'ocr_text'],
        orderBy: 'page_number ASC',
      );
      final buffers = <String, StringBuffer>{};
      for (final doc in docs) {
        buffers[doc['id'] as String] = StringBuffer()
          ..write(doc['title'] ?? '')
          ..write(' ')
          ..write(doc['summary'] ?? '')
          ..write(' ');
      }
      for (final page in pages) {
        final id = page['document_id'] as String;
        buffers[id]?.write((page['ocr_text'] ?? '').toString());
        buffers[id]?.write(' ');
      }
      final batch = txn.batch();
      buffers.forEach((id, buffer) {
        batch.insert(
          'doc_index',
          {'doc_id': id, 'body': buffer.toString().toLowerCase()},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });
      await batch.commit(noResult: true);
    });
    _dirtyDocIds.clear();
    _indexReady = true;
  }

  Future<void> _ensureDocIndex() async {
    if (_indexReady && _dirtyDocIds.isEmpty) return;
    final db = await database;
    if (_dirtyDocIds.isNotEmpty) {
      for (final id in List<String>.from(_dirtyDocIds)) {
        await _refreshDocIndexRow(id, db);
      }
    }
    final docCount =
        ((await db.rawQuery('SELECT COUNT(*) AS c FROM documents')).first['c'] as num?)?.toInt() ?? 0;
    final indexCount =
        ((await db.rawQuery('SELECT COUNT(*) AS c FROM doc_index')).first['c'] as num?)?.toInt() ?? 0;
    if (docCount != indexCount) {
      await _rebuildDocIndex();
    } else {
      _indexReady = true;
    }
  }

  Future<Map<String, String>> _loadIndexBodies(List<String> docIds) async {
    final bodies = <String, String>{};
    if (docIds.isEmpty) return bodies;
    final db = await database;
    const chunkSize = 800;
    for (var i = 0; i < docIds.length; i += chunkSize) {
      final end = (i + chunkSize < docIds.length) ? i + chunkSize : docIds.length;
      final slice = docIds.sublist(i, end);
      if (slice.isEmpty) continue;
      final placeholders = List.filled(slice.length, '?').join(',');
      final rows = await db.rawQuery(
        'SELECT doc_id, body FROM doc_index WHERE doc_id IN ($placeholders)',
        slice,
      );
      for (final row in rows) {
        bodies[row['doc_id'] as String] = (row['body'] ?? '') as String;
      }
    }
    return bodies;
  }

  double _cosineSimilarity(List<double> v1, List<double> v2) {
    if (v1.length != v2.length || v1.isEmpty) return 0.0;
    double dot = 0.0;
    double norm1 = 0.0;
    double norm2 = 0.0;
    for (int i = 0; i < v1.length; i++) {
      dot += v1[i] * v2[i];
      norm1 += v1[i] * v1[i];
      norm2 += v2[i] * v2[i];
    }
    if (norm1 == 0.0 || norm2 == 0.0) return 0.0;
    return dot / (sqrt(norm1) * sqrt(norm2));
  }

  @override
  Future<String> insertPage(PageItem page) async {
    final db = await database;
    final layoutJson = json.encode(page.layoutBlocks.map((b) => b.toMap()).toList());
    final embJson = page.embedding != null ? json.encode(page.embedding) : null;

    await db.insert(
      'pages',
      {
        'id': page.id,
        'document_id': page.documentId,
        'page_number': page.pageNumber,
        'image_path': page.imagePath,
        'ocr_text': page.ocrText,
        'layout_blocks_json': layoutJson,
        'embedding_json': embJson,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _markIndexDirty(page.documentId);
    return page.id;
  }

  PageItem _mapRowToPage(Map<String, dynamic> r) {
    List<LayoutBlock> blocks = [];
    if (r['layout_blocks_json'] != null) {
      try {
        final List list = json.decode(r['layout_blocks_json'] as String);
        blocks = list.map((b) => LayoutBlock.fromMap(Map<String, dynamic>.from(b))).toList();
      } catch (_) {}
    }

    List<double>? emb;
    if (r['embedding_json'] != null) {
      try {
        final List list = json.decode(r['embedding_json'] as String);
        emb = list.map((e) => (e as num).toDouble()).toList();
      } catch (_) {}
    }

    return PageItem(
      id: r['id'] as String,
      documentId: r['document_id'] as String,
      pageNumber: (r['page_number'] as num?)?.toInt() ?? 1,
      imagePath: (r['image_path'] ?? '') as String,
      ocrText: (r['ocr_text'] ?? '') as String,
      layoutBlocks: blocks,
      embedding: emb,
    );
  }

  @override
  Future<List<PageItem>> getPages(String documentId) async {
    final db = await database;
    final rows = await db.query(
      'pages',
      where: 'document_id = ?',
      whereArgs: [documentId],
      orderBy: 'page_number ASC',
    );

    return rows.map(_mapRowToPage).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> vectorSearch(List<double> embedding, {int topK = 10}) async {
    final allDocs = await getAllDocuments();
    final results = <Map<String, dynamic>>[];
    for (final doc in allDocs) {
      if (doc.embedding != null) {
        final sim = _cosineSimilarity(embedding, doc.embedding!);
        if (sim > 0.01) {
          results.add({'id': doc.id, 'score': sim});
        }
      }
    }
    results.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));
    return results.take(topK).toList();
  }

  @override
  Future<List<TagDefinition>> getAllTags() async {
    final db = await database;
    final rows = await db.query('tags', orderBy: 'usage_count DESC');
    return rows.map((r) {
      List<String> aliases = [];
      if (r['aliases_json'] != null) {
        try {
          final List list = json.decode(r['aliases_json'] as String);
          aliases = list.map((e) => e.toString()).toList();
        } catch (_) {}
      }
      return TagDefinition(
        id: r['id'] as String,
        name: r['name'] as String,
        category: (r['category'] ?? '主題') as String,
        aliases: aliases,
        usageCount: (r['usage_count'] as num?)?.toInt() ?? 0,
        createdAt: (r['created_at'] as num?)?.toInt() ?? 0,
        updatedAt: (r['updated_at'] as num?)?.toInt() ?? 0,
        codeSystem: r['code_system'] as String?,
      );
    }).toList();
  }

  @override
  Future<bool> updateTag(TagDefinition tag) async {
    final db = await database;
    final count = await db.update(
      'tags',
      {
        'name': tag.name,
        'category': tag.category,
        'aliases_json': json.encode(tag.aliases),
        'usage_count': tag.usageCount,
        'code_system': tag.codeSystem,
        'updated_at': tag.updatedAt,
      },
      where: 'id = ?',
      whereArgs: [tag.id],
    );
    return count > 0;
  }

  @override
  Future<bool> deleteTag(String tagId) async {
    final db = await database;
    final count = await db.delete('tags', where: 'id = ?', whereArgs: [tagId]);
    return count > 0;
  }

  @override
  Future<Map<String, dynamic>> getStats() async {
    final db = await database;
    final docRes = await db.rawQuery('SELECT COUNT(*) as c FROM documents');
    final docCount = (docRes.first['c'] as num?)?.toInt() ?? 0;

    final pageRes = await db.rawQuery('SELECT COUNT(*) as c FROM pages');
    final pageCount = (pageRes.first['c'] as num?)?.toInt() ?? 0;

    final tagRes = await db.rawQuery('SELECT COUNT(*) as c FROM tags');
    final tagCount = (tagRes.first['c'] as num?)?.toInt() ?? 0;

    final vecRes = await db.rawQuery('SELECT COUNT(*) as c FROM documents WHERE embedding_json IS NOT NULL');
    final vecCount = (vecRes.first['c'] as num?)?.toInt() ?? 0;

    int totalBytes = 0;
    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      final dbFile = File(p.join(appDocDir.path, 'SmartDocSearch', 'koredb_sqlite', 'smart_doc_search.db'));
      if (await dbFile.exists()) {
        totalBytes = await dbFile.length();
      }
    } catch (_) {}

    return {
      'documentCount': docCount,
      'pageCount': pageCount,
      'tagCount': tagCount,
      'vectorCount': vecCount,
      'storageBytes': totalBytes > 0 ? totalBytes : 1024 * 1024,
    };
  }

  /// Exports full database state matching Android KoreDB schema:
  /// { version: "2.0", timestamp: ..., documents: [...], pages: [...], tags: [...] }
  @override
  Future<String> exportBackup() async {
    final docs = await getAllDocuments();
    final allPages = <PageItem>[];
    for (final d in docs) {
      final pList = await getPages(d.id);
      allPages.addAll(pList);
    }
    final tags = await getAllTags();

    final map = {
      'version': '2.0',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'documents': docs.map((d) => d.toMap()).toList(),
      'pages': allPages.map((p) => p.toMap()).toList(),
      'tags': tags.map((t) => t.toMap()).toList(),
    };
    return json.encode(map);
  }

  /// Restores database with ACID transaction protection
  @override
  Future<bool> restoreBackup(String backupJson) async {
    final db = await database;
    final Map<String, dynamic> root = json.decode(backupJson);

    // Force the full-text cache to be rebuilt after a restore.
    _dirtyDocIds.clear();
    _indexReady = false;

    return await db.transaction<bool>((txn) async {
      await txn.delete('pages');
      await txn.delete('documents');
      await txn.delete('tags');
      await txn.delete('doc_index');

      if (root['documents'] is List) {
        for (final item in root['documents']) {
          final doc = Document.fromMap(Map<String, dynamic>.from(item));
          final tagsJson = json.encode(doc.tags.map((t) => t.toMap()).toList());
          final metaJson = json.encode(doc.metadata);
          final embJson = doc.embedding != null ? json.encode(doc.embedding) : null;
          final chSummary = (doc.metadata['chineseSummary'] ?? '').toString();

          await txn.insert(
            'documents',
            {
              'id': doc.id,
              'title': doc.title,
              'source_type': doc.sourceType,
              'file_hash': doc.fileHash,
              'file_path': doc.filePath,
              'page_count': doc.pageCount,
              'summary': doc.summary,
              'chinese_summary': chSummary,
              'detected_language': doc.language,
              'tags_json': tagsJson,
              'metadata_json': metaJson,
              'embedding_json': embJson,
              'created_at': doc.createdAt,
              'updated_at': doc.updatedAt,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }

      if (root['pages'] is List) {
        for (final item in root['pages']) {
          final page = PageItem.fromMap(Map<String, dynamic>.from(item));
          final layoutJson = json.encode(page.layoutBlocks.map((b) => b.toMap()).toList());
          final embJson = page.embedding != null ? json.encode(page.embedding) : null;

          await txn.insert(
            'pages',
            {
              'id': page.id,
              'document_id': page.documentId,
              'page_number': page.pageNumber,
              'image_path': page.imagePath,
              'ocr_text': page.ocrText,
              'layout_blocks_json': layoutJson,
              'embedding_json': embJson,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }

      // Collect and deduplicate tags by normalized name to prevent UNIQUE constraint failure
      final Map<String, Map<String, dynamic>> uniqueTags = {};

      if (root['tags'] is List) {
        for (final item in root['tags']) {
          if (item is! Map) continue;
          final tag = TagDefinition.fromMap(Map<String, dynamic>.from(item));
          final key = tag.name.trim().toLowerCase();
          if (key.isEmpty) continue;

          if (!uniqueTags.containsKey(key)) {
            uniqueTags[key] = {
              'id': tag.id,
              'name': tag.name.trim(),
              'category': tag.category,
              'aliases_json': json.encode(tag.aliases),
              'usage_count': tag.usageCount,
              'code_system': tag.codeSystem,
              'created_at': tag.createdAt,
              'updated_at': tag.updatedAt,
            };
          } else {
            final existing = uniqueTags[key]!;
            final currentCount = (existing['usage_count'] as num?)?.toInt() ?? 0;
            existing['usage_count'] = currentCount + tag.usageCount;
            if ((existing['code_system'] == null || existing['code_system'].toString().isEmpty) &&
                tag.codeSystem != null &&
                tag.codeSystem!.isNotEmpty) {
              existing['code_system'] = tag.codeSystem;
            }
            try {
              final existingAliases = (json.decode(existing['aliases_json'] as String) as List).cast<String>().toSet();
              existingAliases.addAll(tag.aliases);
              existing['aliases_json'] = json.encode(existingAliases.toList());
            } catch (_) {}
            if (tag.updatedAt > (existing['updated_at'] as int? ?? 0)) {
              existing['updated_at'] = tag.updatedAt;
            }
          }
        }
      }

      // Also ensure any tags attached to documents exist in uniqueTags
      if (root['documents'] is List) {
        for (final item in root['documents']) {
          if (item is! Map) continue;
          final doc = Document.fromMap(Map<String, dynamic>.from(item));
          for (final tag in doc.tags) {
            final key = tag.name.trim().toLowerCase();
            if (key.isEmpty) continue;
            if (!uniqueTags.containsKey(key)) {
              uniqueTags[key] = {
                'id': tag.id.isNotEmpty ? tag.id : 'tag_${DateTime.now().microsecondsSinceEpoch}',
                'name': tag.name.trim(),
                'category': tag.category,
                'aliases_json': json.encode([]),
                'usage_count': 1,
                'code_system': tag.codeSystem,
                'created_at': DateTime.now().millisecondsSinceEpoch,
                'updated_at': DateTime.now().millisecondsSinceEpoch,
              };
            } else {
              final existing = uniqueTags[key]!;
              if ((existing['code_system'] == null || existing['code_system'].toString().isEmpty) &&
                  tag.codeSystem != null &&
                  tag.codeSystem!.isNotEmpty) {
                existing['code_system'] = tag.codeSystem;
              }
            }
          }
        }
      }

      for (final tagData in uniqueTags.values) {
        await txn.insert(
          'tags',
          tagData,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      return true;
    });
  }

  @override
  Future<bool> clearAll() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('pages');
      await txn.delete('documents');
      await txn.delete('tags');
      await txn.delete('doc_index');
    });
    _dirtyDocIds.clear();
    _indexReady = false;
    return true;
  }

  @override
  Future<List<Map<String, dynamic>>> renderPdfPages(String pdfPath, String outputDir, {int maxPages = 50}) async {
    return [];
  }

  @override
  Future<List<LayoutBlock>> analyzeLayout(String text) async {
    final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    return lines.map((l) {
      final isTitle = l.length < 50 && (l.startsWith('#') || RegExp(r'^[0-9]+[、.]').hasMatch(l));
      return LayoutBlock(
        type: isTitle ? 'title' : 'paragraph',
        text: l,
        bbox: [10, 10, 400, 50],
      );
    }).toList();
  }

  @override
  Future<bool> openFile(String filePath) async {
    try {
      File file = File(filePath);
      if (!await file.exists()) {
        final fileName = p.basename(filePath);
        // Fallback 1: Check user custom literature directory if set
        try {
          final prefs = await SharedPreferences.getInstance();
          final customPath = prefs.getString(AppConstants.prefLiteratureStoragePath);
          if (customPath != null && customPath.trim().isNotEmpty) {
            final candCustom = File(p.join(customPath.trim(), fileName));
            if (await candCustom.exists()) {
              file = candCustom;
            }
          }
        } catch (_) {}
      }

      if (!await file.exists()) {
        // Fallback 2: Check in system Documents/Smart_Doc/ or legacy folders
        final appDir = await getApplicationDocumentsDirectory();
        final fileName = p.basename(filePath);
        final candidate1 = File(p.join(appDir.path, 'Smart_Doc', fileName));
        if (await candidate1.exists()) {
          file = candidate1;
        } else {
          final candidate2 = File(p.join(appDir.path, 'SmartDocSearch', 'Documents', fileName));
          if (await candidate2.exists()) {
            file = candidate2;
          }
        }
      }
      if (!await file.exists()) return false;

      if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', file.path]);
        return true;
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [file.path]);
        return true;
      } else if (Platform.isMacOS) {
        await Process.run('open', [file.path]);
        return true;
      }
    } catch (e) {
      debugPrint('Desktop openFile error: $e');
    }
    return false;
  }

  @override
  Future<String> getDefaultLiteratureDirectory() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      return p.join(appDir.path, 'Smart_Doc');
    } catch (e) {
      return p.join(Directory.current.path, 'Smart_Doc');
    }
  }

  @override
  Future<String?> copyToDocuments(String sourcePath, String fileName, {String? customTargetDir}) async {
    try {
      String targetDirPath = customTargetDir ?? '';
      if (targetDirPath.isEmpty) {
        try {
          final prefs = await SharedPreferences.getInstance();
          targetDirPath = prefs.getString(AppConstants.prefLiteratureStoragePath) ?? '';
        } catch (_) {}
      }
      if (targetDirPath.isEmpty) {
        targetDirPath = await getDefaultLiteratureDirectory();
      }

      final targetFolder = Directory(targetDirPath);
      if (!await targetFolder.exists()) {
        await targetFolder.create(recursive: true);
      }
      final destPath = p.join(targetFolder.path, fileName);
      await File(sourcePath).copy(destPath);
      return destPath;
    } catch (e) {
      debugPrint('Desktop copyToDocuments error: $e');
      return null;
    }
  }
}
