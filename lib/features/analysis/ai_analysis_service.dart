import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:smart_doc_search/data/datasources/ollama_client.dart';
import 'package:smart_doc_search/data/models/document_model.dart';
import 'package:smart_doc_search/data/repositories/document_repository.dart';

/// Represents a relevant document matched against AI analysis tags.
class AiDocumentMatch {
  final Document document;
  final double score; // 0.0 to 1.0
  final int matchCount;
  final List<String> matchedTags;
  final double confidenceScore;

  AiDocumentMatch({
    required this.document,
    required this.score,
    required this.matchCount,
    required this.matchedTags,
    this.confidenceScore = 0.0,
  });

  int get scorePercent => (score * 100).clamp(0, 100).round();
}

/// A stored historical analysis item (up to 20 items kept).
class AiAnalysisHistoryItem {
  final String id;
  final int timestamp;
  final String textSnippet;
  final String fullText;
  final List<TagItem> tags;
  final String summary;
  final String chineseSummary;
  final String provider;
  final String model;
  final int durationMs;

  AiAnalysisHistoryItem({
    required this.id,
    required this.timestamp,
    required this.textSnippet,
    required this.fullText,
    required this.tags,
    required this.summary,
    this.chineseSummary = '',
    required this.provider,
    required this.model,
    this.durationMs = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'timestamp': timestamp,
      'textSnippet': textSnippet,
      'fullText': fullText,
      'tags': tags.map((t) => t.toMap()).toList(),
      'summary': summary,
      'chineseSummary': chineseSummary,
      'provider': provider,
      'model': model,
      'durationMs': durationMs,
    };
  }

  factory AiAnalysisHistoryItem.fromMap(Map<String, dynamic> map) {
    final rawTags = map['tags'] as List? ?? [];
    return AiAnalysisHistoryItem(
      id: (map['id'] ?? '').toString(),
      timestamp: (map['timestamp'] as num?)?.toInt() ?? 0,
      textSnippet: (map['textSnippet'] ?? '').toString(),
      fullText: (map['fullText'] ?? '').toString(),
      tags: rawTags.map((t) => TagItem.fromMap(Map<String, dynamic>.from(t))).toList(),
      summary: (map['summary'] ?? '').toString(),
      chineseSummary: (map['chineseSummary'] ?? '').toString(),
      provider: (map['provider'] ?? '').toString(),
      model: (map['model'] ?? '').toString(),
      durationMs: (map['durationMs'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Result of loading a text file.
class LoadedTextFile {
  final String fileName;
  final int fileSize;
  final String content;

  LoadedTextFile({
    required this.fileName,
    required this.fileSize,
    required this.content,
  });

  String get formattedSize {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}

/// Service handling AI Analysis page logic:
/// - Relevant document retrieval via C.9 tag-weighted matching algorithm
/// - Importing analysis results as official KoreDB / SQLite documents
/// - Text file picking and validation
/// - History recording and retrieval
class AiAnalysisService {
  static const String prefHistoryKey = 'pref_ai_analysis_history';
  static const int maxHistoryCount = 20;
  static const int maxTextLength = 50000;
  static const int maxFileSize = 5 * 1024 * 1024; // 5 MB

  final DocumentRepository repository;
  final OllamaClient ollamaClient;

  AiAnalysisService({
    required this.repository,
    required this.ollamaClient,
  });

  /// Executes tag-based document matching based on Algorithm C.9:
  /// Mode:
  /// - WEIGHTED (default): score = Σ(doc.tag.confidence * query.tag.confidence) / |query.tags|
  /// - AND: document must contain all query tags
  /// - OR: document must contain at least one query tag
  Future<List<AiDocumentMatch>> searchRelevantDocuments({
    required List<TagItem> queryTags,
    String mode = 'WEIGHTED',
    int limit = 50,
  }) async {
    if (queryTags.isEmpty) return [];

    final allDocs = await repository.getAllDocuments();
    final queryTagMap = <String, TagItem>{};
    for (final t in queryTags) {
      final key = t.name.trim().toLowerCase();
      if (key.isNotEmpty) {
        queryTagMap[key] = t;
      }
    }
    final queryNames = queryTagMap.keys.toSet();
    if (queryNames.isEmpty) return [];

    final matches = <AiDocumentMatch>[];

    for (final doc in allDocs) {
      final docTagMap = <String, TagItem>{};
      for (final t in doc.tags) {
        final key = t.name.trim().toLowerCase();
        if (key.isNotEmpty) {
          docTagMap[key] = t;
        }
      }

      final matchedTagNames = <String>[];
      double weightedSum = 0.0;

      for (final qName in queryNames) {
        if (docTagMap.containsKey(qName)) {
          final qTag = queryTagMap[qName]!;
          final dTag = docTagMap[qName]!;
          matchedTagNames.add(dTag.name);

          final qConf = qTag.confidence;
          final dConf = dTag.confidence;
          weightedSum += (qConf * dConf);
        }
      }

      final matchCount = matchedTagNames.length;
      if (matchCount == 0) continue;

      if (mode.toUpperCase() == 'AND') {
        if (matchCount < queryNames.length) continue;
        final score = (weightedSum / queryNames.length).clamp(0.0, 1.0);
        matches.add(AiDocumentMatch(
          document: doc,
          score: score,
          matchCount: matchCount,
          matchedTags: matchedTagNames,
          confidenceScore: weightedSum,
        ));
      } else if (mode.toUpperCase() == 'OR') {
        final score = (matchCount / queryNames.length).clamp(0.0, 1.0);
        matches.add(AiDocumentMatch(
          document: doc,
          score: score,
          matchCount: matchCount,
          matchedTags: matchedTagNames,
          confidenceScore: weightedSum,
        ));
      } else {
        // WEIGHTED (default)
        final score = (weightedSum / queryNames.length).clamp(0.0, 1.0);
        matches.add(AiDocumentMatch(
          document: doc,
          score: score,
          matchCount: matchCount,
          matchedTags: matchedTagNames,
          confidenceScore: weightedSum,
        ));
      }
    }

    // Sort by score desc, then matchCount desc, then updatedAt desc
    matches.sort((a, b) {
      final c = b.score.compareTo(a.score);
      if (c != 0) return c;
      final mc = b.matchCount.compareTo(a.matchCount);
      if (mc != 0) return mc;
      return b.document.updatedAt.compareTo(a.document.updatedAt);
    });

    return matches.take(limit).toList();
  }

  /// Imports an analysis session as an official document into the repository.
  /// - Saves original text to managed storage and copies to Documents/Smart_Doc
  /// - Inserts Document record (sourceType = 'text')
  /// - Inserts PageItem record (page 1)
  /// - Triggers repository reactive change stream
  Future<Document> importFromAnalysis({
    required String text,
    required List<TagItem> tags,
    required String summary,
    String? chineseSummary,
    String? customTitle,
  }) async {
    final trimmedText = text.trim();
    if (trimmedText.isEmpty) {
      throw Exception('文檔內容不能為空');
    }

    // 1. Determine title
    String title = customTitle?.trim() ?? '';
    if (title.isEmpty) {
      final firstLine = trimmedText.split('\n').first.trim();
      if (firstLine.isNotEmpty && firstLine.length <= 50) {
        title = firstLine;
      } else if (firstLine.length > 50) {
        title = '${firstLine.substring(0, 47)}...';
      } else {
        final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
        title = 'AI 分析文字文檔 ($dateStr)';
      }
    }

    // 2. Compute hash
    final bytes = utf8.encode(trimmedText);
    final fileHash = sha256.convert(bytes).toString();

    // 3. Save text file to managed directory and copy to Documents/Smart_Doc
    final appDir = await getApplicationDocumentsDirectory();
    final docStorageDir = Directory(p.join(appDir.path, 'documents', fileHash));
    if (!await docStorageDir.exists()) {
      await docStorageDir.create(recursive: true);
    }
    final timestampStr = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final fileName = 'text_$timestampStr.txt';
    final savedFile = File(p.join(docStorageDir.path, fileName));
    await savedFile.writeAsString(trimmedText, encoding: utf8);

    String? documentsCopyPath;
    try {
      documentsCopyPath = await repository.copyToDocuments(savedFile.path, fileName);
    } catch (_) {}
    final effectiveFilePath = (documentsCopyPath != null && documentsCopyPath.isNotEmpty)
        ? documentsCopyPath
        : savedFile.path;

    // 4. Create Document & PageItem
    final docId = 'doc_${DateTime.now().millisecondsSinceEpoch}_${const Uuid().v4().substring(0, 8)}';
    final now = DateTime.now().millisecondsSinceEpoch;

    final doc = Document(
      id: docId,
      title: title,
      sourceType: 'text',
      fileHash: fileHash,
      filePath: effectiveFilePath,
      pageCount: 1,
      summary: summary,
      tags: tags,
      metadata: {
        'chineseSummary': chineseSummary ?? '',
        'importedFrom': 'ai_analysis',
        'originalCharCount': trimmedText.length,
        'importedAt': now,
      },
      language: 'zh-TW',
      createdAt: now,
      updatedAt: now,
    );

    final page = PageItem(
      id: 'page_${docId}_1',
      documentId: docId,
      pageNumber: 1,
      imagePath: '',
      ocrText: trimmedText,
      layoutBlocks: [
        LayoutBlock(type: 'text', bbox: [0, 0, 100, 100], text: trimmedText),
      ],
    );

    await repository.saveDocument(doc);
    await repository.savePage(page);

    // Notify data changed across all tabs
    repository.notifyDataChanged(immediate: true);

    return doc;
  }

  /// Picks and loads a plain text file (.txt, .md, .csv, .json).
  /// Verifies file size (<= 5 MB) and decodes UTF-8.
  Future<LoadedTextFile?> pickTextFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'md', 'markdown', 'csv', 'json'],
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) return null;
    final picked = result.files.first;

    if (picked.size > maxFileSize) {
      throw Exception('檔案大小超過 5 MB 上限（目前大小：${(picked.size / (1024 * 1024)).toStringAsFixed(1)} MB）');
    }

    String content = '';
    if (picked.bytes != null) {
      try {
        content = utf8.decode(picked.bytes!);
      } catch (_) {
        content = latin1.decode(picked.bytes!);
      }
    } else if (picked.path != null) {
      final file = File(picked.path!);
      try {
        content = await file.readAsString(encoding: utf8);
      } catch (_) {
        content = await file.readAsString(encoding: latin1);
      }
    }

    return LoadedTextFile(
      fileName: picked.name,
      fileSize: picked.size,
      content: content,
    );
  }

  /// Saves an analysis record to history (keeps maximum 20).
  Future<void> saveHistory(AiAnalysisHistoryItem item) async {
    final prefs = await SharedPreferences.getInstance();
    final history = await loadHistory();

    // Insert at front
    history.insert(0, item);

    // Keep max 20
    final trimmed = history.take(maxHistoryCount).toList();
    final encoded = json.encode(trimmed.map((e) => e.toMap()).toList());
    await prefs.setString(prefHistoryKey, encoded);
  }

  /// Loads analysis history from SharedPreferences.
  Future<List<AiAnalysisHistoryItem>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefHistoryKey);
    if (raw == null || raw.isEmpty) return [];

    try {
      final List list = json.decode(raw);
      return list
          .map((e) => AiAnalysisHistoryItem.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Deletes a single history item by id.
  Future<void> deleteHistoryItem(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final history = await loadHistory();
    history.removeWhere((item) => item.id == id);
    final encoded = json.encode(history.map((e) => e.toMap()).toList());
    await prefs.setString(prefHistoryKey, encoded);
  }

  /// Clears all analysis history.
  Future<void> clearAllHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(prefHistoryKey);
  }
}
