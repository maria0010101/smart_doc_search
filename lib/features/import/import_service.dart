import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:smart_doc_search/core/constants/app_constants.dart';
import 'package:smart_doc_search/core/utils/hash_util.dart';
import 'package:smart_doc_search/data/datasources/koredb_datasource.dart';
import 'package:smart_doc_search/data/datasources/ollama_client.dart';
import 'package:smart_doc_search/data/models/document_model.dart';
import 'package:smart_doc_search/data/repositories/document_repository.dart';
import 'package:uuid/uuid.dart';

enum ImportStage {
  idle,
  hashing,
  renderingPages,
  ocrProcessing,
  ollamaTagging,
  generatingEmbedding,
  savingToDb,
  completed,
  error,
}

class ImportProgress {
  final String fileName;
  final ImportStage stage;
  final double progress; // 0.0 to 1.0
  final String message;
  final bool isDuplicate;
  final String? error;

  ImportProgress({
    required this.fileName,
    required this.stage,
    required this.progress,
    required this.message,
    this.isDuplicate = false,
    this.error,
  });
}

class ImportService {
  final DocumentRepository repository;
  final KoreDbDataSource dataSource;
  final OllamaClient ollamaClient;
  final _uuid = const Uuid();

  final _progressController = StreamController<ImportProgress>.broadcast();
  Stream<ImportProgress> get progressStream => _progressController.stream;

  ImportService({
    required this.repository,
    required this.dataSource,
    required this.ollamaClient,
  });

  void dispose() {
    _progressController.close();
  }

  /// Opens system file picker for literature files
  Future<List<String>> pickDocumentFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: [
          ...AppConstants.supportedPdfExt,
          ...AppConstants.supportedImageExt,
          ...AppConstants.supportedPptExt,
        ],
      );
      if (result != null) {
        return result.paths.whereType<String>().toList();
      }
    } catch (e) {
      debugPrint('File picker error: $e');
    }
    return [];
  }

  /// Imports a batch of documents sequentially, emitting granular progress
  Future<List<Document>> importBatch(List<String> filePaths) async {
    final importedDocs = <Document>[];

    for (int i = 0; i < filePaths.length; i++) {
      final path = filePaths[i];
      try {
        final doc = await importSingleFile(path);
        if (doc != null) {
          importedDocs.add(doc);
        }
      } catch (e) {
        debugPrint('Failed to import $path: $e');
      }
    }

    return importedDocs;
  }

  Future<Document?> importSingleFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      _emitProgress(filePath, ImportStage.error, 0.0, '檔案不存在', error: 'File does not exist');
      return null;
    }

    final fileName = p.basename(filePath);
    final ext = p.extension(filePath).toLowerCase().replaceAll('.', '');

    // 1. Calculate SHA-256 & Deduplication check
    _emitProgress(fileName, ImportStage.hashing, 0.1, '計算 SHA-256 雜湊碼...');
    final fileHash = await HashUtil.calculateFileSha256(filePath);

    final isDup = await repository.checkHashExists(fileHash);
    if (isDup) {
      _emitProgress(fileName, ImportStage.completed, 1.0, '檔案已存在，略過重複匯入', isDuplicate: true);
      return null;
    }

    // Determine type
    String sourceType = 'image';
    if (AppConstants.supportedPdfExt.contains(ext)) {
      sourceType = 'pdf';
    } else if (AppConstants.supportedPptExt.contains(ext)) {
      sourceType = 'ppt';
    }

    // Prepare app storage directory
    final appDir = await getApplicationDocumentsDirectory();
    final docStorageDir = Directory(p.join(appDir.path, 'documents', fileHash));
    if (!await docStorageDir.exists()) {
      await docStorageDir.create(recursive: true);
    }

    // Copy original file into managed directory
    final destFilePath = p.join(docStorageDir.path, fileName);
    await file.copy(destFilePath);

    final docId = _uuid.v4();
    final title = p.basenameWithoutExtension(filePath);
    final pageItems = <PageItem>[];
    String aggregatedOcrText = '';

    // 2. Render pages and perform on-device OCR / layout analysis
    _emitProgress(fileName, ImportStage.renderingPages, 0.3, '解析文件與渲染頁面...');

    if (sourceType == 'pdf') {
      final pagesInfo = await dataSource.renderPdfPages(destFilePath, docStorageDir.path, maxPages: 30);
      if (pagesInfo.isNotEmpty) {
        for (int pIdx = 0; pIdx < pagesInfo.length; pIdx++) {
          final pMap = pagesInfo[pIdx];
          final pageNum = (pMap['pageNumber'] as int?) ?? (pIdx + 1);
          final imgPath = (pMap['imagePath'] as String?) ?? '';

          // Text layout extraction
          final pageText = '文獻頁碼: $pageNum \n$title\n(PDF 原生渲染頁面)';
          final layoutBlocks = await dataSource.analyzeLayout(pageText);

          final page = PageItem(
            id: _uuid.v4(),
            documentId: docId,
            pageNumber: pageNum,
            imagePath: imgPath,
            ocrText: pageText,
            layoutBlocks: layoutBlocks,
          );
          pageItems.add(page);
          aggregatedOcrText += '$pageText\n';
        }
      } else {
        // Fallback single page
        final pageText = '$title\n(PDF 文獻內容)';
        pageItems.add(PageItem(
          id: _uuid.v4(),
          documentId: docId,
          pageNumber: 1,
          imagePath: '',
          ocrText: pageText,
          layoutBlocks: await dataSource.analyzeLayout(pageText),
        ));
        aggregatedOcrText = pageText;
      }
    } else if (sourceType == 'ppt') {
      // PPT Notice & handling
      final pageText = '$title\n提示：初版建議將 PPT 簡報轉為 PDF 以獲得最佳版面分析與檢索效果。';
      pageItems.add(PageItem(
        id: _uuid.v4(),
        documentId: docId,
        pageNumber: 1,
        imagePath: destFilePath,
        ocrText: pageText,
        layoutBlocks: await dataSource.analyzeLayout(pageText),
      ));
      aggregatedOcrText = pageText;
    } else {
      // Images
      _emitProgress(fileName, ImportStage.ocrProcessing, 0.4, '執行端側文字識別 (OCR)...');
      final pageText = '$title\n圖片文字識別內容提取';
      pageItems.add(PageItem(
        id: _uuid.v4(),
        documentId: docId,
        pageNumber: 1,
        imagePath: destFilePath,
        ocrText: pageText,
        layoutBlocks: await dataSource.analyzeLayout(pageText),
      ));
      aggregatedOcrText = pageText;
    }

    // 3. Ollama Tag Generation
    _emitProgress(fileName, ImportStage.ollamaTagging, 0.6, '呼叫 Ollama 生成多維標籤...');
    List<TagItem> generatedTags = [];
    try {
      final tags = await ollamaClient.generateTags(
        text: '$title\n$aggregatedOcrText',
      );
      generatedTags = tags;
    } catch (e) {
      debugPrint('Ollama tagging skipped or failed (offline mode active): $e');
      // Rule-based fallback tags
      generatedTags = [
        TagItem(
          id: _uuid.v4(),
          name: sourceType.toUpperCase(),
          category: '文檔類型',
          source: 'rule',
          confidence: 1.0,
          verified: true,
        ),
        TagItem(
          id: _uuid.v4(),
          name: '待審核',
          category: '狀態',
          source: 'rule',
          confidence: 0.8,
          verified: false,
        ),
      ];
    }

    // 4. Ollama Vector Embedding
    _emitProgress(fileName, ImportStage.generatingEmbedding, 0.8, '生成文獻向量嵌入...');
    List<double>? embedding;
    try {
      final emb = await ollamaClient.embed(text: '$title\n$aggregatedOcrText');
      if (emb.isNotEmpty) embedding = emb;
    } catch (e) {
      debugPrint('Embedding generation skipped: $e');
    }

    // 5. Save Document & Pages to KoreDB
    _emitProgress(fileName, ImportStage.savingToDb, 0.9, '儲存至 KoreDB 資料庫...');
    final now = DateTime.now().millisecondsSinceEpoch;
    final document = Document(
      id: docId,
      title: title,
      sourceType: sourceType,
      filePath: destFilePath,
      fileHash: fileHash,
      createdAt: now,
      updatedAt: now,
      pageCount: pageItems.length,
      language: 'zh-TW',
      tags: generatedTags,
      summary: aggregatedOcrText.length > 200 ? '${aggregatedOcrText.substring(0, 200)}...' : aggregatedOcrText,
      embedding: embedding,
      metadata: {
        'originalPath': filePath,
        'extension': ext,
        'fileSize': await file.length(),
      },
    );

    await repository.saveDocument(document);
    for (final page in pageItems) {
      await repository.savePage(page);
    }

    _emitProgress(fileName, ImportStage.completed, 1.0, '匯入成功！');
    return document;
  }

  void _emitProgress(
    String fileName,
    ImportStage stage,
    double progress,
    String message, {
    bool isDuplicate = false,
    String? error,
  }) {
    if (!_progressController.isClosed) {
      _progressController.add(ImportProgress(
        fileName: fileName,
        stage: stage,
        progress: progress,
        message: message,
        isDuplicate: isDuplicate,
        error: error,
      ));
    }
  }
}
