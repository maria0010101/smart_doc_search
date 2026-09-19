import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as syncfusion;
import 'package:smart_doc_search/core/constants/app_constants.dart';
import 'package:smart_doc_search/core/utils/hash_util.dart';
import 'package:smart_doc_search/core/utils/text_normalizer.dart';
import 'package:smart_doc_search/data/datasources/koredb_datasource.dart';
import 'package:smart_doc_search/data/datasources/ollama_client.dart';
import 'package:smart_doc_search/data/models/document_model.dart';
import 'package:smart_doc_search/data/repositories/document_repository.dart';
import 'package:smart_doc_search/features/search/hybrid_search_service.dart';

void main() {
  group('1. HashUtil SHA-256 Tests', () {
    test('calculateBytesSha256 produces valid SHA-256 hash', () {
      final bytes = utf8.encode('Hello World Literature');
      final hash = HashUtil.calculateBytesSha256(bytes);
      expect(hash.length, 64);
      expect(hash, isNotEmpty);
      // Deterministic
      expect(HashUtil.calculateBytesSha256(bytes), equals(hash));
    });
  });

  group('2. TextNormalizer & Tag Fusion Tests', () {
    test('normalizes full-width to half-width and maps synonyms', () {
      // Full-width characters
      final tag1 = TextNormalizer.normalizeTag('ＭＬ');
      expect(tag1, '機器學習');

      final tag2 = TextNormalizer.normalizeTag('   Machine Learning   ');
      expect(tag2, '機器學習');

      final tag3 = TextNormalizer.normalizeTag('ＤＬ');
      expect(tag3, '深度學習');

      final tag4 = TextNormalizer.normalizeTag('ＡＩ');
      expect(tag4, '人工智慧');
    });

    test('cleanTagList deduplicates and normalizes list', () {
      final raw = ['ＭＬ', 'Machine Learning', '機器學習', 'NLP', '自然語言處理', 'NLP'];
      final cleaned = TextNormalizer.cleanTagList(raw);
      expect(cleaned, contains('機器學習'));
      expect(cleaned, contains('自然語言處理'));
      expect(cleaned.length, 2);
    });
  });

  group('3. Document & Tag Data Model Tests', () {
    test('Document model serialization roundtrip', () {
      final doc = Document(
        id: 'doc-123',
        title: '機器學習論文集',
        sourceType: 'pdf',
        filePath: '/data/user/0/doc.pdf',
        fileHash: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        createdAt: 1700000000000,
        updatedAt: 1700000000000,
        pageCount: 15,
        language: 'zh-TW',
        tags: [
          TagItem(
            id: 'tag-1',
            name: '機器學習',
            category: '主題',
            confidence: 0.95,
            source: 'ai_text',
            verified: true,
          ),
        ],
        summary: '這是一篇關於機器學習的測試摘要。',
        embedding: [0.12, 0.45, 0.88],
      );

      final jsonStr = doc.toJson();
      final parsed = Document.fromJson(jsonStr);

      expect(parsed.id, doc.id);
      expect(parsed.title, doc.title);
      expect(parsed.tags.length, 1);
      expect(parsed.tags.first.name, '機器學習');
      expect(parsed.tags.first.verified, true);
      expect(parsed.embedding, equals([0.12, 0.45, 0.88]));
    });

    test('PageItem model serialization roundtrip', () {
      final page = PageItem(
        id: 'page-1',
        documentId: 'doc-123',
        pageNumber: 1,
        imagePath: '/data/page_1.png',
        ocrText: '第一章 緒論\n這是機器學習的開端。',
        layoutBlocks: [
          LayoutBlock(type: 'title', bbox: [10, 10, 400, 40], text: '第一章 緒論'),
          LayoutBlock(type: 'paragraph', bbox: [10, 50, 400, 100], text: '這是機器學習的開端。'),
        ],
      );

      final jsonStr = page.toJson();
      final parsed = PageItem.fromJson(jsonStr);

      expect(parsed.id, 'page-1');
      expect(parsed.pageNumber, 1);
      expect(parsed.layoutBlocks.length, 2);
      expect(parsed.layoutBlocks.first.type, 'title');
    });
  });

  group('4. KoreDB Storage & Hybrid Search Tests', () {
    late KoreDbDataSource dataSource;
    late DocumentRepository repository;
    late OllamaClient ollamaClient;
    late HybridSearchService searchService;

    setUp(() {
      dataSource = KoreDbNativeDataSource();
      repository = DocumentRepository(dataSource: dataSource);
      ollamaClient = OllamaClient();
      searchService = HybridSearchService(dataSource: dataSource, ollamaClient: ollamaClient);
    });

    test('CRUD operations and tag-based queries (AND / OR)', () async {
      final doc1 = Document(
        id: 'doc-1',
        title: '深度學習在醫學影像之應用',
        sourceType: 'pdf',
        filePath: '/storage/doc1.pdf',
        fileHash: 'hash-111',
        createdAt: 1700000000000,
        updatedAt: 1700000000000,
        pageCount: 10,
        tags: [
          TagItem(id: 't1', name: '深度學習', category: '領域'),
          TagItem(id: 't2', name: '醫學', category: '對象'),
        ],
        summary: '探討深度學習於胸部 X 光檢測',
        embedding: [0.9, 0.1, 0.0],
      );

      final doc2 = Document(
        id: 'doc-2',
        title: '自然語言處理技術進展',
        sourceType: 'pdf',
        filePath: '/storage/doc2.pdf',
        fileHash: 'hash-222',
        createdAt: 1700000010000,
        updatedAt: 1700000010000,
        pageCount: 8,
        tags: [
          TagItem(id: 't3', name: '自然語言處理', category: '領域'),
          TagItem(id: 't4', name: '大型語言模型', category: '主題'),
        ],
        summary: '探討 Transformer 架構與提示工程',
        embedding: [0.0, 0.8, 0.6],
      );

      await repository.saveDocument(doc1);
      await repository.saveDocument(doc2);

      // Check hash existence
      expect(await repository.checkHashExists('hash-111'), isTrue);
      expect(await repository.checkHashExists('hash-999'), isFalse);

      // Tag queries
      final andQuery = await dataSource.queryByTags(['深度學習', '醫學'], mode: 'AND');
      expect(andQuery.length, 1);
      expect(andQuery.first.id, 'doc-1');

      final orQuery = await dataSource.queryByTags(['深度學習', '自然語言處理'], mode: 'OR');
      expect(orQuery.length, 2);

      // Hybrid Search
      final searchRes = await searchService.executeSearch(
        queryText: '醫學影像',
        selectedTags: ['深度學習'],
        enableSemanticSearch: false,
      );
      expect(searchRes.items.isNotEmpty, isTrue);
      expect(searchRes.items.first.document.id, 'doc-1');

      // Tag Merging Test
      final mergeOk = await repository.mergeTags('t1', '進階深度學習');
      expect(mergeOk, isTrue);

      final updatedDoc = await repository.getDocument('doc-1');
      expect(updatedDoc?.tags.any((t) => t.name == '進階深度學習'), isTrue);

      // Delete Document
      await repository.deleteDocument('doc-1');
      expect(await repository.getDocument('doc-1'), isNull);
    });
  });

  group('5. Multi-Provider AI Configuration & Parsing Tests', () {
    test('AiProvider enum and serialization works correctly', () {
      expect(AiProvider.fromId('ollama'), equals(AiProvider.ollama));
      expect(AiProvider.fromId('deepseek'), equals(AiProvider.deepseek));
      expect(AiProvider.fromId('openai'), equals(AiProvider.openai));
      expect(AiProvider.fromId('claude'), equals(AiProvider.claude));
      expect(AiProvider.fromId('google'), equals(AiProvider.google));
      expect(AiProvider.fromId('fastapi'), equals(AiProvider.fastapi));
      expect(AiProvider.fromId('unknown'), equals(AiProvider.ollama)); // fallback
    });

    test('OllamaClient supports multi-provider switching and properties', () {
      final client = OllamaClient(
        provider: AiProvider.deepseek,
        host: AppConstants.defaultDeepSeekHost,
        textModel: 'deepseek-chat',
        apiKey: 'test-sk-12345',
      );

      expect(client.isCloudProvider, isTrue);
      expect(client.providerDisplayName, 'DeepSeek API');
      expect(client.host, 'https://api.deepseek.com');
      expect(client.apiKey, 'test-sk-12345');

      // Switch to Claude
      client.provider = AiProvider.claude;
      client.host = AppConstants.defaultClaudeHost;
      client.textModel = 'claude-3-5-haiku-20241022';
      expect(client.providerDisplayName, 'Anthropic Claude API');
      expect(client.isCloudProvider, isTrue);

      // Switch to Google
      client.provider = AiProvider.google;
      client.host = AppConstants.defaultGoogleHost;
      client.textModel = 'gemini-1.5-flash';
      expect(client.providerDisplayName, 'Google Gemini API');

      // Switch to OpenAI
      client.provider = AiProvider.openai;
      client.host = AppConstants.defaultOpenAiHost;
      client.textModel = 'gpt-4o-mini';
      expect(client.providerDisplayName, 'OpenAI GPT API');

      // Switch to Ollama
      client.provider = AiProvider.ollama;
      expect(client.isCloudProvider, isFalse);
    });

    test('OllamaClient testConnection requires API key for cloud providers', () async {
      final client = OllamaClient(
        provider: AiProvider.deepseek,
        apiKey: '', // Empty key
      );
      final ok = await client.testConnection();
      expect(ok, isFalse);
    });
  });

  group('6. Medical Terminology, Disease Classification & AI Summary Tests', () {
    test('TextNormalizer normalizes medical terms and disease abbreviations', () {
      expect(TextNormalizer.normalizeTag('DM'), equals('糖尿病'));
      expect(TextNormalizer.normalizeTag('diabetes'), equals('糖尿病'));
      expect(TextNormalizer.normalizeTag('HTN'), equals('高血壓'));
      expect(TextNormalizer.normalizeTag('CAD'), equals('冠狀動脈心臟病'));
      expect(TextNormalizer.normalizeTag('COPD'), equals('慢性阻塞性肺病'));
      expect(TextNormalizer.normalizeTag('AMI'), equals('急性心肌梗塞'));
      expect(TextNormalizer.normalizeTag('CVA'), equals('腦中風'));
      expect(TextNormalizer.normalizeTag('ICD-10'), equals('ICD-10疾病編碼'));
    });

    test('AiAnalysisResult correctly stores medical categories and summaries', () {
      final result = AiAnalysisResult(
        tags: [
          TagItem(id: '1', name: '第2型糖尿病', category: '疾病/症狀'),
          TagItem(id: '2', name: 'E11', category: '疾病分類編碼'),
          TagItem(id: '3', name: '胰島素阻抗', category: '醫學術語'),
        ],
        summary: 'A clinical research study investigating Type 2 Diabetes Mellitus interventions.',
        chineseSummary: '本臨床研究探討第2型糖尿病之介入療法與血糖調控成果。',
        detectedLanguage: 'en',
        medicalTerms: ['胰島素阻抗'],
        diseasesAndSymptoms: ['第2型糖尿病'],
        classificationCodes: ['E11'],
      );

      expect(result.tags.length, 3);
      expect(result.tags.any((t) => t.category == '疾病/症狀'), isTrue);
      expect(result.tags.any((t) => t.category == '疾病分類編碼'), isTrue);
      expect(result.tags.any((t) => t.category == '醫學術語'), isTrue);
      expect(result.displaySummary, contains('本臨床研究探討第2型糖尿病'));
      expect(result.detectedLanguage, 'en');
    });

    test('Document model stores Chinese summary and medical tags in metadata', () {
      final doc = Document(
        id: 'med-doc-1',
        title: 'Management of Hypertension and Cardiovascular Risk',
        sourceType: 'pdf',
        filePath: '/storage/medical/doc1.pdf',
        fileHash: 'hash-med-1',
        createdAt: 1700000000000,
        updatedAt: 1700000000000,
        language: 'en',
        tags: [
          TagItem(id: 't-1', name: '高血壓', category: '疾病/症狀'),
          TagItem(id: 't-2', name: 'I10', category: '疾病分類編碼'),
          TagItem(id: 't-3', name: '動脈粥狀硬化', category: '醫學術語'),
        ],
        summary: 'Clinical trial evaluating blood pressure targets.',
        metadata: {
          'chineseSummary': '評估降血壓目標值與心血管風險之大型臨床試驗。',
        },
      );

      expect(doc.metadata['chineseSummary'], contains('評估降血壓目標值'));
      expect(doc.tags.length, 3);
    });
  });

  group('7. Native Text Extraction & Document Copy Tests', () {
    test('Extracts native text from PDF without OCR if embedded text exists', () {
      final samplePdf = File('/home/hpd/下載/王稟合.pdf');
      if (samplePdf.existsSync()) {
        final bytes = samplePdf.readAsBytesSync();
        final pdfDoc = syncfusion.PdfDocument(inputBytes: bytes);
        final extractor = syncfusion.PdfTextExtractor(pdfDoc);
        final text = extractor.extractText();
        expect(text, isNotEmpty);
        expect(text.trim().length, greaterThan(10));
        pdfDoc.dispose();
      }
    });
  });
}

