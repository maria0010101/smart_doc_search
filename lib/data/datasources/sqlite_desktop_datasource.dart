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
        version: 2,
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
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            try {
              await db.execute('ALTER TABLE tags ADD COLUMN code_system TEXT;');
            } catch (_) {}
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
    return count > 0;
  }

  @override
  Future<bool> deleteDocument(String id) async {
    final db = await database;
    await db.delete('pages', where: 'document_id = ?', whereArgs: [id]);
    final count = await db.delete('documents', where: 'id = ?', whereArgs: [id]);
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
    final db = await database;
    var candidates = await getAllDocuments();

    // 1. Tag filtering
    if (tags.isNotEmpty) {
      candidates = candidates.where((doc) {
        final docTagNames = doc.tags.map((t) => t.name.toLowerCase()).toSet();
        if (tagMode == 'AND') {
          return tags.every((qt) => docTagNames.contains(qt.toLowerCase()));
        } else {
          return tags.any((qt) => docTagNames.contains(qt.toLowerCase()));
        }
      }).toList();
    }

    // Load all pages for full-text search and page matching
    final pagesRows = await db.query('pages', orderBy: 'page_number ASC');
    final Map<String, List<PageItem>> docPages = {};
    for (final r in pagesRows) {
      final docId = r['document_id'] as String;
      docPages.putIfAbsent(docId, () => []).add(_mapRowToPage(r));
    }

    // 2. Score candidates
    final scored = <DocumentHit>[];
    for (final doc in candidates) {
      final pages = docPages[doc.id] ?? [];
      final pageTexts = pages.map((p) => p.ocrText).join(' ');
      final fullText = '${doc.title} ${doc.summary} $pageTexts';

      double kwScore = 0.0;
      String? snippet;

      if (keywords.isNotEmpty) {
        for (final p in pages) {
          for (final kw in keywords) {
            final count = RegExp(RegExp.escape(kw), caseSensitive: false).allMatches(p.ocrText).length;
            if (count > 0) {
              kwScore += count * 1.5 / (count + 1.0);
            }
          }
        }
        for (final kw in keywords) {
          final count = RegExp(RegExp.escape(kw), caseSensitive: false).allMatches(fullText).length;
          if (count > 0 && kwScore == 0.0) {
            kwScore += count * 1.5 / (count + 1.0);
          }
        }
      }

      // 使用 TagPageCalibrator 智慧解析實質命中頁碼（優先取用標籤正確頁數，嚴格排除目錄頁誤導）
      final matchedPageNumber = TagPageCalibrator.resolveSubstantivePageForSearchHit(
        searchKeywords: keywords,
        searchTags: tags,
        docTags: doc.tags,
        docPages: pages,
        docSummary: doc.summary,
      );

      // 提取符合該實質命中頁面之引註片段
      if (keywords.isNotEmpty && pages.isNotEmpty) {
        final targetPage = pages.firstWhere(
          (p) => p.pageNumber == matchedPageNumber,
          orElse: () => pages.first,
        );
        for (final kw in keywords) {
          final idx = targetPage.ocrText.toLowerCase().indexOf(kw.toLowerCase());
          if (idx != -1) {
            final start = max(0, idx - 50);
            final end = min(targetPage.ocrText.length, idx + kw.length + 50);
            snippet = '...${targetPage.ocrText.substring(start, end).trim()}...';
            break;
          }
        }
      }
      if (snippet == null && keywords.isNotEmpty) {
        for (final kw in keywords) {
          final idx = fullText.toLowerCase().indexOf(kw.toLowerCase());
          if (idx != -1) {
            final start = max(0, idx - 50);
            final end = min(fullText.length, idx + kw.length + 50);
            snippet = '...${fullText.substring(start, end).trim()}...';
            break;
          }
        }
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
          if (docTagNames.contains(t.toLowerCase())) {
            matchedTags.add(t);
          }
        }
        tagScore = matchedTags.length / tags.length;
      }

      double totalScore = (keywords.isEmpty && semanticEmbedding == null && tags.isEmpty)
          ? 1.0
          : (AppConstants.weightKeyword * kwScore) + (AppConstants.weightVector * vecScore) + (AppConstants.weightTag * tagScore);

      if (totalScore > 0 || (keywords.isEmpty && tags.isEmpty)) {
        scored.add(DocumentHit(
          document: doc,
          score: totalScore,
          highlight: snippet,
          matchedTags: matchedTags,
          pageNumber: matchedPageNumber,
        ));
      }
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    final paged = scored.skip(offset).take(limit).toList();
    sw.stop();

    return SearchResult(
      items: paged,
      total: scored.length,
      tookMs: sw.elapsedMilliseconds,
    );
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

    return await db.transaction<bool>((txn) async {
      await txn.delete('pages');
      await txn.delete('documents');
      await txn.delete('tags');

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
    });
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
