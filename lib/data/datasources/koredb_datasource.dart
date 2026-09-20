import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:smart_doc_search/core/constants/app_constants.dart';
import 'package:smart_doc_search/data/models/document_model.dart';

abstract class KoreDbDataSource {
  Future<String> insertDocument(Document doc);
  Future<bool> updateDocument(Document doc);
  Future<bool> deleteDocument(String id);
  Future<Document?> getDocument(String id);
  Future<List<Document>> getAllDocuments();
  Future<List<Document>> queryByTags(List<String> tags, {String mode = 'AND'});
  Future<SearchResult> hybridSearch({
    List<String> keywords = const [],
    List<String> tags = const [],
    String tagMode = 'AND',
    List<double>? semanticEmbedding,
    int limit = 20,
    int offset = 0,
  });
  Future<String> insertPage(PageItem page);
  Future<List<PageItem>> getPages(String documentId);
  Future<List<Map<String, dynamic>>> vectorSearch(List<double> embedding, {int topK = 10});
  Future<List<TagDefinition>> getAllTags();
  Future<bool> updateTag(TagDefinition tag);
  Future<bool> deleteTag(String tagId);
  Future<Map<String, dynamic>> getStats();
  Future<String> exportBackup();
  Future<bool> restoreBackup(String backupJson);
  Future<bool> clearAll();

  // Tools
  Future<List<Map<String, dynamic>>> renderPdfPages(String pdfPath, String outputDir, {int maxPages = 50});
  Future<List<LayoutBlock>> analyzeLayout(String text);
  Future<bool> openFile(String filePath);
  Future<String?> copyToDocuments(String sourcePath, String fileName);
}

class KoreDbNativeDataSource implements KoreDbDataSource {
  static const MethodChannel _koreDbChannel = MethodChannel(AppConstants.koredbChannel);
  static const MethodChannel _toolsChannel = MethodChannel(AppConstants.nativeToolsChannel);

  bool _isAndroidPlatform() {
    return !kIsWeb && Platform.isAndroid;
  }

  // Pure Dart Fallback (Used when running on Linux Desktop or in tests)
  final Map<String, Document> _fallbackDocs = {};
  final Map<String, List<PageItem>> _fallbackPages = {};
  final Map<String, TagDefinition> _fallbackTags = {};

  @override
  Future<String> insertDocument(Document doc) async {
    if (_isAndroidPlatform()) {
      try {
        final id = await _koreDbChannel.invokeMethod<String>('insertDocument', {
          'document': doc.toJson(),
        });
        return id ?? doc.id;
      } catch (e) {
        debugPrint('KoreDB native error, falling back to local memory: $e');
      }
    }
    _fallbackDocs[doc.id] = doc;
    for (final tag in doc.tags) {
      final tid = tag.id.isNotEmpty ? tag.id : tag.name;
      final existing = _fallbackTags[tid];
      _fallbackTags[tid] = TagDefinition(
        id: tid,
        name: tag.name,
        category: tag.category,
        usageCount: (existing?.usageCount ?? 0) + 1,
        createdAt: existing?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
    }
    return doc.id;
  }

  @override
  Future<bool> updateDocument(Document doc) async {
    if (_isAndroidPlatform()) {
      try {
        final ok = await _koreDbChannel.invokeMethod<bool>('updateDocument', {
          'document': doc.toJson(),
        });
        return ok ?? false;
      } catch (e) {
        debugPrint('KoreDB updateDocument error: $e');
      }
    }
    if (_fallbackDocs.containsKey(doc.id)) {
      _fallbackDocs[doc.id] = doc;
      return true;
    }
    return false;
  }

  @override
  Future<bool> deleteDocument(String id) async {
    if (_isAndroidPlatform()) {
      try {
        final ok = await _koreDbChannel.invokeMethod<bool>('deleteDocument', {
          'id': id,
        });
        return ok ?? false;
      } catch (e) {
        debugPrint('KoreDB deleteDocument error: $e');
      }
    }
    _fallbackDocs.remove(id);
    _fallbackPages.remove(id);
    return true;
  }

  @override
  Future<Document?> getDocument(String id) async {
    if (_isAndroidPlatform()) {
      try {
        final jsonStr = await _koreDbChannel.invokeMethod<String>('getDocument', {'id': id});
        if (jsonStr != null && jsonStr.isNotEmpty) {
          return Document.fromJson(jsonStr);
        }
      } catch (e) {
        debugPrint('KoreDB getDocument error: $e');
      }
    }
    return _fallbackDocs[id];
  }

  @override
  Future<List<Document>> getAllDocuments() async {
    if (_isAndroidPlatform()) {
      try {
        final jsonStr = await _koreDbChannel.invokeMethod<String>('getAllDocuments');
        if (jsonStr != null && jsonStr.isNotEmpty) {
          final List list = json.decode(jsonStr);
          return list.map((e) => Document.fromMap(Map<String, dynamic>.from(e))).toList();
        }
      } catch (e) {
        debugPrint('KoreDB getAllDocuments error: $e');
      }
    }
    return _fallbackDocs.values.toList();
  }

  @override
  Future<List<Document>> queryByTags(List<String> tags, {String mode = 'AND'}) async {
    if (_isAndroidPlatform()) {
      try {
        final jsonStr = await _koreDbChannel.invokeMethod<String>('queryByTags', {
          'tags': tags,
          'mode': mode,
        });
        if (jsonStr != null && jsonStr.isNotEmpty) {
          final List list = json.decode(jsonStr);
          return list.map((e) => Document.fromMap(Map<String, dynamic>.from(e))).toList();
        }
      } catch (e) {
        debugPrint('KoreDB queryByTags error: $e');
      }
    }

    if (tags.isEmpty) return getAllDocuments();
    final lowerTags = tags.map((t) => t.trim().toLowerCase()).toList();

    return _fallbackDocs.values.where((doc) {
      final docTagNames = doc.tags.map((t) => t.name.trim().toLowerCase()).toSet();
      if (mode.toUpperCase() == 'OR') {
        return lowerTags.any((t) => docTagNames.contains(t));
      } else {
        return lowerTags.every((t) => docTagNames.contains(t));
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
    if (_isAndroidPlatform()) {
      try {
        final jsonStr = await _koreDbChannel.invokeMethod<String>('hybridSearch', {
          'keywords': keywords,
          'tags': tags,
          'tagMode': tagMode,
          'semanticEmbedding': semanticEmbedding,
          'limit': limit,
          'offset': offset,
        });
        if (jsonStr != null && jsonStr.isNotEmpty) {
          return SearchResult.fromMap(json.decode(jsonStr));
        }
      } catch (e) {
        debugPrint('KoreDB hybridSearch error: $e');
      }
    }

    // Fallback Dart implementation of Hybrid Search
    var candidates = await queryByTags(tags, mode: tagMode);
    final hits = <DocumentHit>[];

    for (final doc in candidates) {
      final pageTexts = (_fallbackPages[doc.id] ?? []).map((p) => p.ocrText).join(' ');
      final fullText = '${doc.title} ${doc.summary} $pageTexts';

      double kwScore = 0.0;
      String? highlight;
      if (keywords.isNotEmpty) {
        for (final kw in keywords) {
          final count = RegExp(RegExp.escape(kw), caseSensitive: false).allMatches(fullText).length;
          if (count > 0) {
            kwScore += count * 1.5 / (count + 1.0);
            if (highlight == null) {
              final idx = fullText.toLowerCase().indexOf(kw.toLowerCase());
              final start = max(0, idx - 30);
              final end = min(fullText.length, idx + kw.length + 30);
              highlight = '...${fullText.substring(start, end).trim()}...';
            }
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
        final docTags = doc.tags.map((t) => t.name.toLowerCase()).toSet();
        for (final t in tags) {
          if (docTags.contains(t.toLowerCase())) {
            matchedTags.add(t);
          }
        }
        tagScore = matchedTags.length / tags.length;
      }

      final score = (keywords.isEmpty && semanticEmbedding == null && tags.isEmpty)
          ? 1.0
          : (AppConstants.weightKeyword * kwScore) +
              (AppConstants.weightVector * vecScore) +
              (AppConstants.weightTag * tagScore);

      hits.add(DocumentHit(
        document: doc,
        score: score,
        highlight: highlight,
        matchedTags: matchedTags,
      ));
    }

    hits.sort((a, b) => b.score.compareTo(a.score));
    final total = hits.length;
    final paged = hits.skip(offset).take(limit).toList();

    return SearchResult(
      items: paged,
      total: total,
      tookMs: sw.elapsedMilliseconds,
    );
  }

  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.isEmpty || b.isEmpty) return 0.0;
    final len = min(a.length, b.length);
    double dot = 0.0;
    double normA = 0.0;
    double normB = 0.0;
    for (int i = 0; i < len; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    if (normA == 0.0 || normB == 0.0) return 0.0;
    return dot / (sqrt(normA) * sqrt(normB));
  }

  @override
  Future<String> insertPage(PageItem page) async {
    if (_isAndroidPlatform()) {
      try {
        final id = await _koreDbChannel.invokeMethod<String>('insertPage', {
          'page': page.toJson(),
        });
        return id ?? page.id;
      } catch (e) {
        debugPrint('KoreDB insertPage error: $e');
      }
    }
    final list = _fallbackPages.putIfAbsent(page.documentId, () => []);
    list.removeWhere((p) => p.id == page.id);
    list.add(page);
    return page.id;
  }

  @override
  Future<List<PageItem>> getPages(String documentId) async {
    if (_isAndroidPlatform()) {
      try {
        final jsonStr = await _koreDbChannel.invokeMethod<String>('getPages', {
          'documentId': documentId,
        });
        if (jsonStr != null && jsonStr.isNotEmpty) {
          final List list = json.decode(jsonStr);
          return list.map((e) => PageItem.fromMap(Map<String, dynamic>.from(e))).toList();
        }
      } catch (e) {
        debugPrint('KoreDB getPages error: $e');
      }
    }
    return _fallbackPages[documentId] ?? [];
  }

  @override
  Future<List<Map<String, dynamic>>> vectorSearch(List<double> embedding, {int topK = 10}) async {
    if (_isAndroidPlatform()) {
      try {
        final jsonStr = await _koreDbChannel.invokeMethod<String>('vectorSearch', {
          'embedding': embedding,
          'topK': topK,
        });
        if (jsonStr != null && jsonStr.isNotEmpty) {
          final List list = json.decode(jsonStr);
          return list.map((e) => Map<String, dynamic>.from(e)).toList();
        }
      } catch (e) {
        debugPrint('KoreDB vectorSearch error: $e');
      }
    }
    final results = <Map<String, dynamic>>[];
    for (final doc in _fallbackDocs.values) {
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
    if (_isAndroidPlatform()) {
      try {
        final jsonStr = await _koreDbChannel.invokeMethod<String>('getAllTags');
        if (jsonStr != null && jsonStr.isNotEmpty) {
          final List list = json.decode(jsonStr);
          return list.map((e) => TagDefinition.fromMap(Map<String, dynamic>.from(e))).toList();
        }
      } catch (e) {
        debugPrint('KoreDB getAllTags error: $e');
      }
    }
    return _fallbackTags.values.toList();
  }

  @override
  Future<bool> updateTag(TagDefinition tag) async {
    if (_isAndroidPlatform()) {
      try {
        final ok = await _koreDbChannel.invokeMethod<bool>('updateTag', {
          'tag': tag.toJson(),
        });
        return ok ?? false;
      } catch (e) {
        debugPrint('KoreDB updateTag error: $e');
      }
    }
    _fallbackTags[tag.id] = tag;
    return true;
  }

  @override
  Future<bool> deleteTag(String tagId) async {
    if (_isAndroidPlatform()) {
      try {
        final ok = await _koreDbChannel.invokeMethod<bool>('deleteTag', {'id': tagId});
        return ok ?? false;
      } catch (e) {
        debugPrint('KoreDB deleteTag error: $e');
      }
    }
    _fallbackTags.remove(tagId);
    return true;
  }

  @override
  Future<Map<String, dynamic>> getStats() async {
    if (_isAndroidPlatform()) {
      try {
        final jsonStr = await _koreDbChannel.invokeMethod<String>('getStats');
        if (jsonStr != null && jsonStr.isNotEmpty) {
          return Map<String, dynamic>.from(json.decode(jsonStr));
        }
      } catch (e) {
        debugPrint('KoreDB getStats error: $e');
      }
    }
    return {
      'documentCount': _fallbackDocs.length,
      'pageCount': _fallbackPages.values.fold<int>(0, (sum, list) => sum + list.length),
      'tagCount': _fallbackTags.length,
      'vectorCount': _fallbackDocs.values.where((d) => d.embedding != null).length,
      'storageBytes': 1024 * 1024,
    };
  }

  @override
  Future<String> exportBackup() async {
    if (_isAndroidPlatform()) {
      try {
        final jsonStr = await _koreDbChannel.invokeMethod<String>('exportBackup');
        if (jsonStr != null && jsonStr.isNotEmpty) return jsonStr;
      } catch (e) {
        debugPrint('KoreDB exportBackup error: $e');
      }
    }
    return json.encode({
      'version': '2.0',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'documents': _fallbackDocs.values.map((d) => d.toMap()).toList(),
      'pages': _fallbackPages.values.expand((list) => list.map((p) => p.toMap())).toList(),
      'tags': _fallbackTags.values.map((t) => t.toMap()).toList(),
    });
  }

  @override
  Future<bool> restoreBackup(String backupJson) async {
    if (_isAndroidPlatform()) {
      try {
        final ok = await _koreDbChannel.invokeMethod<bool>('restoreBackup', {
          'backupJson': backupJson,
        });
        return ok ?? false;
      } catch (e) {
        debugPrint('KoreDB restoreBackup error: $e');
      }
    }
    try {
      final map = json.decode(backupJson);
      _fallbackDocs.clear();
      _fallbackPages.clear();
      _fallbackTags.clear();
      if (map['documents'] is List) {
        for (final item in map['documents']) {
          final doc = Document.fromMap(Map<String, dynamic>.from(item));
          _fallbackDocs[doc.id] = doc;
        }
      }
      if (map['pages'] is List) {
        for (final item in map['pages']) {
          final p = PageItem.fromMap(Map<String, dynamic>.from(item));
          _fallbackPages.putIfAbsent(p.documentId, () => []).add(p);
        }
      }
      if (map['tags'] is List) {
        for (final item in map['tags']) {
          final t = TagDefinition.fromMap(Map<String, dynamic>.from(item));
          _fallbackTags[t.id] = t;
        }
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<bool> clearAll() async {
    if (_isAndroidPlatform()) {
      try {
        final ok = await _koreDbChannel.invokeMethod<bool>('clearAll');
        return ok ?? false;
      } catch (e) {
        debugPrint('KoreDB clearAll error: $e');
      }
    }
    _fallbackDocs.clear();
    _fallbackPages.clear();
    _fallbackTags.clear();
    return true;
  }

  @override
  Future<List<Map<String, dynamic>>> renderPdfPages(
    String pdfPath,
    String outputDir, {
    int maxPages = 50,
  }) async {
    if (_isAndroidPlatform()) {
      try {
        final res = await _toolsChannel.invokeMethod<List>('renderPdfPages', {
          'pdfPath': pdfPath,
          'outputDir': outputDir,
          'maxPages': maxPages,
        });
        if (res != null) {
          return res.map((e) => Map<String, dynamic>.from(e)).toList();
        }
      } catch (e) {
        debugPrint('renderPdfPages error: $e');
      }
    }
    return [];
  }

  @override
  Future<List<LayoutBlock>> analyzeLayout(String text) async {
    if (_isAndroidPlatform()) {
      try {
        final jsonStr = await _toolsChannel.invokeMethod<String>('analyzeLayout', {
          'text': text,
        });
        if (jsonStr != null && jsonStr.isNotEmpty) {
          final List list = json.decode(jsonStr);
          return list.map((e) => LayoutBlock.fromMap(Map<String, dynamic>.from(e))).toList();
        }
      } catch (e) {
        debugPrint('analyzeLayout error: $e');
      }
    }
    // Fallback layout segmentation
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
    if (_isAndroidPlatform()) {
      try {
        final res = await _toolsChannel.invokeMethod<bool>('openFile', {'filePath': filePath});
        return res ?? false;
      } catch (e) {
        debugPrint('openFile error: $e');
        return false;
      }
    }
    return false;
  }

  @override
  Future<String?> copyToDocuments(String sourcePath, String fileName) async {
    if (_isAndroidPlatform()) {
      try {
        final res = await _toolsChannel.invokeMethod<String>('copyToDocuments', {
          'sourcePath': sourcePath,
          'fileName': fileName,
        });
        if (res != null && res.isNotEmpty) return res;
      } catch (e) {
        debugPrint('copyToDocuments native error: $e');
      }
    }
    // Fallback: Copy to application documents folder
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final docsDir = Directory('${appDir.path}/Documents/Smart_Doc');
      if (!await docsDir.exists()) await docsDir.create(recursive: true);
      final dest = File('${docsDir.path}/$fileName');
      await File(sourcePath).copy(dest.path);
      return dest.path;
    } catch (e) {
      debugPrint('copyToDocuments fallback error: $e');
      return null;
    }
  }
}
