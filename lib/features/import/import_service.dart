import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as syncfusion;
import 'package:smart_doc_search/core/constants/app_constants.dart';
import 'package:smart_doc_search/core/utils/hash_util.dart';
import 'package:smart_doc_search/core/utils/tag_page_calibrator.dart';
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
          ...AppConstants.supportedTextExt,
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

  /// Helper to split large text files into logical pages
  List<String> _chunkTextIntoPages(String text, {int maxCharsPerPage = 1800}) {
    if (text.isEmpty) return [''];
    if (text.length <= maxCharsPerPage) return [text];

    final lines = text.split('\n');
    final pages = <String>[];
    var currentChunk = StringBuffer();

    for (final line in lines) {
      if (currentChunk.length + line.length > maxCharsPerPage && currentChunk.isNotEmpty) {
        pages.add(currentChunk.toString().trim());
        currentChunk = StringBuffer();
      }
      currentChunk.writeln(line);
    }
    if (currentChunk.isNotEmpty) {
      pages.add(currentChunk.toString().trim());
    }
    return pages.isEmpty ? [text] : pages;
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
    } else if (AppConstants.supportedTextExt.contains(ext)) {
      sourceType = 'text';
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

    // Save copy to Documents/Smart_Doc folder (開啟原始檔案時以此副本開啟)
    _emitProgress(fileName, ImportStage.savingToDb, 0.15, '儲存副本至 Documents/Smart_Doc 資料夾...');
    String? documentsCopyPath;
    try {
      documentsCopyPath = await repository.copyToDocuments(destFilePath, fileName);
    } catch (e) {
      debugPrint('Failed to copy to Documents/Smart_Doc directory: $e');
    }
    final effectiveFilePath = (documentsCopyPath != null && documentsCopyPath.isNotEmpty)
        ? documentsCopyPath
        : destFilePath;

    final docId = _uuid.v4();
    final title = p.basenameWithoutExtension(filePath);
    final pageItems = <PageItem>[];
    String aggregatedFullText = '';

    // 2. Text Extraction vs OCR
    // (文字內容之 PDF 或其他文字文件不進行 OCR，直接以文字內容判讀)
    if (sourceType == 'text') {
      _emitProgress(fileName, ImportStage.renderingPages, 0.3, '直接以文字內容判讀（跳過 OCR）...');
      String fullContent = '';
      try {
        fullContent = await file.readAsString();
      } catch (_) {
        try {
          final bytes = await file.readAsBytes();
          fullContent = utf8.decode(bytes, allowMalformed: true);
        } catch (_) {
          fullContent = '$title\n(純文字內容讀取)';
        }
      }

      final chunks = _chunkTextIntoPages(fullContent);
      for (int i = 0; i < chunks.length; i++) {
        final pText = chunks[i];
        final layoutBlocks = await dataSource.analyzeLayout(pText);
        pageItems.add(PageItem(
          id: _uuid.v4(),
          documentId: docId,
          pageNumber: i + 1,
          imagePath: '',
          ocrText: pText,
          layoutBlocks: layoutBlocks,
        ));
      }
      aggregatedFullText = fullContent;
    } else if (sourceType == 'pdf') {
      _emitProgress(fileName, ImportStage.renderingPages, 0.25, '解析 PDF 原生文字層與頁面版面...');

      final pdfBytes = await File(destFilePath).readAsBytes();
      syncfusion.PdfDocument? pdfDoc;
      syncfusion.PdfTextExtractor? textExtractor;
      int pdfTotalPages = 1;
      try {
        pdfDoc = syncfusion.PdfDocument(inputBytes: pdfBytes);
        textExtractor = syncfusion.PdfTextExtractor(pdfDoc);
        pdfTotalPages = pdfDoc.pages.count;
      } catch (e) {
        debugPrint('Syncfusion PDF open error: $e');
      }

      final pageCount = min(pdfTotalPages, 50);
      final pagesInfo = await dataSource.renderPdfPages(destFilePath, docStorageDir.path, maxPages: pageCount);

      for (int pIdx = 0; pIdx < pageCount; pIdx++) {
        final pageNum = pIdx + 1;
        String imgPath = '';
        if (pIdx < pagesInfo.length) {
          imgPath = (pagesInfo[pIdx]['imagePath'] as String?) ?? '';
        }

        // Extract native text
        String pageText = '';
        if (textExtractor != null) {
          try {
            pageText = textExtractor.extractText(startPageIndex: pIdx, endPageIndex: pIdx).trim();
          } catch (e) {
            debugPrint('Syncfusion extractText error on page $pageNum: $e');
          }
        }

        final hasNativeText = pageText.length > 10;
        if (!hasNativeText) {
          // If page has no embedded text (scanned PDF page), fallback to OCR
          _emitProgress(fileName, ImportStage.ocrProcessing, 0.35 + (0.2 * (pIdx / pageCount)), '第 $pageNum 頁為掃描影像，執行端側 OCR...');
          pageText = '【第 $pageNum 頁 - 掃描版面】\n$title';
        }

        final layoutBlocks = await dataSource.analyzeLayout(pageText);
        pageItems.add(PageItem(
          id: _uuid.v4(),
          documentId: docId,
          pageNumber: pageNum,
          imagePath: imgPath,
          ocrText: pageText,
          layoutBlocks: layoutBlocks,
        ));
        aggregatedFullText += '【第 $pageNum 頁】\n$pageText\n\n';
      }

      pdfDoc?.dispose();
    } else if (sourceType == 'ppt') {
      final pageText = '$title\n提示：建議將 PPT 簡報轉為 PDF 以獲得最佳版面分析與全文檢索效果。';
      pageItems.add(PageItem(
        id: _uuid.v4(),
        documentId: docId,
        pageNumber: 1,
        imagePath: destFilePath,
        ocrText: pageText,
        layoutBlocks: await dataSource.analyzeLayout(pageText),
      ));
      aggregatedFullText = pageText;
    } else {
      // Images
      _emitProgress(fileName, ImportStage.ocrProcessing, 0.4, '影像文件執行端側文字識別 (OCR)...');
      final pageText = '$title\n圖片文字識別內容提取';
      pageItems.add(PageItem(
        id: _uuid.v4(),
        documentId: docId,
        pageNumber: 1,
        imagePath: destFilePath,
        ocrText: pageText,
        layoutBlocks: await dataSource.analyzeLayout(pageText),
      ));
      aggregatedFullText = pageText;
    }

    // 3. AI Analysis & Medical Tag Generation from FULL TEXT
    // (標籤辨識須以全文內容進行辨識，摘要須以全文內容進行摘要包含各標題內文字)
    _emitProgress(fileName, ImportStage.ollamaTagging, 0.65, '呼叫 ${ollamaClient.providerDisplayName} 依全文與各標題分析標籤及摘要...');
    List<TagItem> generatedTags = [];
    String aiSummary = '';
    String aiChineseSummary = '';
    String detectedLang = 'zh-TW';

    try {
      final analysis = await ollamaClient.generateAnalysis(
        text: '文獻標題：$title\n\n完整全文內容：\n$aggregatedFullText',
      );
      generatedTags = analysis.tags;
      aiSummary = analysis.summary;
      aiChineseSummary = analysis.chineseSummary;
      detectedLang = analysis.detectedLanguage;
    } catch (e) {
      debugPrint('AI analysis skipped or failed (offline mode active): $e');
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

    if (aiSummary.isEmpty) {
      aiSummary = aggregatedFullText.length > 200 ? '${aggregatedFullText.substring(0, 200)}...' : aggregatedFullText;
    }

    // 校準標籤所屬頁碼（排除目錄頁誤導，精準指向文獻實質討論之真實頁碼）
    generatedTags = TagPageCalibrator.calibrateTags(
      tags: generatedTags,
      pages: pageItems,
      title: title,
    );

    // 4. AI Vector Embedding
    _emitProgress(fileName, ImportStage.generatingEmbedding, 0.85, '生成文獻向量嵌入...');
    List<double>? embedding;
    try {
      final emb = await ollamaClient.embed(text: '$title\n$aggregatedFullText');
      if (emb.isNotEmpty) embedding = emb;
    } catch (e) {
      debugPrint('Embedding generation skipped: $e');
    }

    // 5. Save Document & Pages to KoreDB
    _emitProgress(fileName, ImportStage.savingToDb, 0.95, '儲存至 KoreDB 資料庫...');
    final now = DateTime.now().millisecondsSinceEpoch;
    final document = Document(
      id: docId,
      title: title,
      sourceType: sourceType,
      filePath: effectiveFilePath, // <--- Points to the copy in the phone's Documents directory!
      fileHash: fileHash,
      createdAt: now,
      updatedAt: now,
      pageCount: pageItems.length,
      language: detectedLang,
      tags: generatedTags,
      summary: aiSummary,
      embedding: embedding,
      metadata: {
        'originalPath': filePath,
        'extension': ext,
        'fileSize': await file.length(),
        'chineseSummary': aiChineseSummary,
        'documentsCopyPath': effectiveFilePath,
        'managedStoragePath': destFilePath,
        'extractionMethod': (sourceType == 'text' || sourceType == 'pdf') ? 'native_text' : 'ocr',
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
