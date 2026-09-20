import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import 'package:smart_doc_search/core/constants/app_constants.dart';
import 'package:smart_doc_search/core/utils/security_util.dart';
import 'package:smart_doc_search/data/datasources/koredb_datasource.dart';
import 'package:smart_doc_search/data/datasources/ollama_client.dart';
import 'package:smart_doc_search/data/models/document_model.dart';
import 'package:smart_doc_search/data/repositories/document_repository.dart';
import 'package:smart_doc_search/features/analysis/ai_analysis_service.dart';
import 'package:smart_doc_search/features/analysis/ai_analysis_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DocumentRepository repository;
  late KoreDbNativeDataSource dataSource;
  late OllamaClient ollamaClient;
  late AiAnalysisService analysisService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final tempDocDir = await Directory.systemTemp.createTemp('smart_doc_analysis_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getApplicationDocumentsDirectory') {
          return tempDocDir.path;
        }
        return null;
      },
    );

    dataSource = KoreDbNativeDataSource();
    repository = DocumentRepository(dataSource: dataSource);
    ollamaClient = OllamaClient();
    analysisService = AiAnalysisService(
      repository: repository,
      ollamaClient: ollamaClient,
    );

    // Seed test documents
    final doc1 = Document(
      id: 'doc_1',
      title: '第2型糖尿病與心血管併發症研究',
      sourceType: 'pdf',
      filePath: '/mock/path/doc_1.pdf',
      fileHash: 'hash_1',
      pageCount: 5,
      summary: '探討第2型糖尿病患者之心血管風險與 SGLT2 抑制劑之療效。',
      tags: [
        TagItem(id: 't1', name: '第2型糖尿病', category: '疾病/症狀', confidence: 0.95),
        TagItem(id: 't2', name: '心血管疾病', category: '疾病/症狀', confidence: 0.90),
        TagItem(id: 't3', name: 'E11', category: '疾病分類編碼', confidence: 0.98),
        TagItem(id: 't4', name: 'SGLT2抑制劑', category: '醫學術語', confidence: 0.85),
      ],
      createdAt: 1000,
      updatedAt: 1000,
    );

    final doc2 = Document(
      id: 'doc_2',
      title: '高血壓臨床治療指引',
      sourceType: 'pdf',
      filePath: '/mock/path/doc_2.pdf',
      fileHash: 'hash_2',
      pageCount: 3,
      summary: '原發性高血壓之診斷標準與降壓藥物選用指引。',
      tags: [
        TagItem(id: 't5', name: '高血壓', category: '疾病/症狀', confidence: 0.92),
        TagItem(id: 't6', name: '心血管疾病', category: '疾病/症狀', confidence: 0.80),
        TagItem(id: 't7', name: 'I10', category: '疾病分類編碼', confidence: 0.95),
      ],
      createdAt: 2000,
      updatedAt: 2000,
    );

    final doc3 = Document(
      id: 'doc_3',
      title: '卷積神經網路於醫學影像辨識之應用',
      sourceType: 'text',
      filePath: '/mock/path/doc_3.txt',
      fileHash: 'hash_3',
      pageCount: 1,
      summary: '利用深度學習與 CNN 技術進行 X 光影像肺部病灶自動辨識。',
      tags: [
        TagItem(id: 't8', name: '深度學習', category: '方法', confidence: 0.95),
        TagItem(id: 't9', name: '卷積神經網路', category: '方法', confidence: 0.90),
        TagItem(id: 't10', name: '醫學影像', category: '對象', confidence: 0.88),
      ],
      createdAt: 3000,
      updatedAt: 3000,
    );

    await repository.saveDocument(doc1);
    await repository.saveDocument(doc2);
    await repository.saveDocument(doc3);
  });

  group('1. SecurityUtil API Key Encryption Tests (FR-C-04, C.10)', () {
    test('Masking API key displays prefix and suffix without exposing credential', () {
      expect(SecurityUtil.maskKey(''), '未設定');
      expect(SecurityUtil.maskKey('12345'), '********');
      expect(SecurityUtil.maskKey('sk-proj-1234567890abcdef'), 'sk-pro...cdef');
      expect(SecurityUtil.maskKey('AIzaSyAbCdEfGhIjKlMnOpQrStUvWxYz'), 'AIzaSy...WxYz');
    });

    test('Encryption and Decryption roundtrip preserves exact secret', () {
      const originalKey = 'sk-proj-my-secret-key-12345!@#';
      final encrypted = SecurityUtil.encrypt(originalKey);

      expect(encrypted, isNot(originalKey));
      expect(encrypted.startsWith('enc:v1:'), isTrue);

      final decrypted = SecurityUtil.decrypt(encrypted);
      expect(decrypted, originalKey);
    });

    test('Decryption gracefully handles unencrypted legacy keys', () {
      const legacyKey = 'plain_old_key_123';
      expect(SecurityUtil.decrypt(legacyKey), legacyKey);
      expect(SecurityUtil.decrypt(''), '');
    });

    test('Save and read encrypted API key in SharedPreferences', () async {
      final prefs = await SharedPreferences.getInstance();
      const openAiKey = 'sk-proj-test-openai-credential';

      await SecurityUtil.saveEncryptedKey(prefs, AppConstants.prefOpenAiApiKey, openAiKey);
      final rawStored = prefs.getString(AppConstants.prefOpenAiApiKey);
      expect(rawStored, isNotNull);
      expect(rawStored!.startsWith('enc:v1:'), isTrue);

      final decrypted = SecurityUtil.getDecryptedKey(prefs, AppConstants.prefOpenAiApiKey);
      expect(decrypted, openAiKey);
    });

    test('One-click clear all API keys removes credentials for all providers', () async {
      final prefs = await SharedPreferences.getInstance();
      await SecurityUtil.saveEncryptedKey(prefs, AppConstants.prefOpenAiApiKey, 'key1');
      await SecurityUtil.saveEncryptedKey(prefs, AppConstants.prefClaudeApiKey, 'key2');
      await SecurityUtil.saveEncryptedKey(prefs, AppConstants.prefGoogleApiKey, 'key3');
      await SecurityUtil.saveEncryptedKey(prefs, AppConstants.prefDeepSeekApiKey, 'key4');

      await SecurityUtil.clearAllApiKeys(prefs);

      expect(SecurityUtil.getDecryptedKey(prefs, AppConstants.prefOpenAiApiKey), '');
      expect(SecurityUtil.getDecryptedKey(prefs, AppConstants.prefClaudeApiKey), '');
      expect(SecurityUtil.getDecryptedKey(prefs, AppConstants.prefGoogleApiKey), '');
      expect(SecurityUtil.getDecryptedKey(prefs, AppConstants.prefDeepSeekApiKey), '');
    });
  });

  group('2. Tag-based Document Matching Algorithm C.9 Tests (FR-C-05)', () {
    test('WEIGHTED mode ranks documents by confidence-weighted match score', () async {
      final queryTags = [
        TagItem(id: 'q1', name: '第2型糖尿病', category: '疾病/症狀', confidence: 0.9),
        TagItem(id: 'q2', name: '心血管疾病', category: '疾病/症狀', confidence: 0.8),
      ];

      final matches = await analysisService.searchRelevantDocuments(
        queryTags: queryTags,
        mode: 'WEIGHTED',
      );

      // doc1 matches both tags:
      // score = (0.9 * 0.95 + 0.8 * 0.90) / 2 = (0.855 + 0.72) / 2 = 0.7875
      // doc2 matches 1 tag ('心血管疾病'):
      // score = (0.8 * 0.80) / 2 = 0.32
      // doc3 matches 0 tags.
      expect(matches.length, 2);
      expect(matches[0].document.id, 'doc_1');
      expect(matches[0].matchCount, 2);
      expect(matches[0].score, closeTo(0.7875, 0.001));
      expect(matches[0].scorePercent, 79);

      expect(matches[1].document.id, 'doc_2');
      expect(matches[1].matchCount, 1);
      expect(matches[1].score, closeTo(0.32, 0.001));
      expect(matches[1].scorePercent, 32);
    });

    test('AND mode only returns documents containing ALL query tags', () async {
      final queryTags = [
        TagItem(id: 'q1', name: '第2型糖尿病', category: '疾病/症狀', confidence: 0.9),
        TagItem(id: 'q2', name: '心血管疾病', category: '疾病/症狀', confidence: 0.8),
      ];

      final matches = await analysisService.searchRelevantDocuments(
        queryTags: queryTags,
        mode: 'AND',
      );

      expect(matches.length, 1);
      expect(matches.first.document.id, 'doc_1');
      expect(matches.first.matchedTags, containsAll(['第2型糖尿病', '心血管疾病']));
    });

    test('OR mode returns documents matching any tag with normalized ratio score', () async {
      final queryTags = [
        TagItem(id: 'q1', name: '高血壓', category: '疾病/症狀', confidence: 0.9),
        TagItem(id: 'q2', name: '深度學習', category: '方法', confidence: 0.9),
      ];

      final matches = await analysisService.searchRelevantDocuments(
        queryTags: queryTags,
        mode: 'OR',
      );

      expect(matches.length, 2);
      final matchedIds = matches.map((m) => m.document.id).toList();
      expect(matchedIds, containsAll(['doc_2', 'doc_3']));
    });

    test('Empty query tags returns empty list gracefully', () async {
      final matches = await analysisService.searchRelevantDocuments(queryTags: []);
      expect(matches, isEmpty);
    });
  });

  group('3. Analysis History Management Tests (FR-C-08)', () {
    test('Saves and retrieves analysis records up to 20 maximum items', () async {
      for (int i = 1; i <= 25; i++) {
        await analysisService.saveHistory(AiAnalysisHistoryItem(
          id: 'item_$i',
          timestamp: 1000 + i,
          textSnippet: 'Snippet $i',
          fullText: 'Full content $i',
          tags: [TagItem(id: 't_$i', name: 'Tag_$i', category: '主題')],
          summary: 'Summary $i',
          provider: 'Ollama',
          model: 'qwen2.5:3b',
        ));
      }

      final history = await analysisService.loadHistory();
      expect(history.length, 20);
      // Newest item first
      expect(history.first.id, 'item_25');
      expect(history.last.id, 'item_6');
    });

    test('Deletes individual history item and clears all history', () async {
      await analysisService.saveHistory(AiAnalysisHistoryItem(
        id: 'h1',
        timestamp: 100,
        textSnippet: 'S1',
        fullText: 'F1',
        tags: [],
        summary: 'Sum1',
        provider: 'OpenAI',
        model: 'gpt-4o-mini',
      ));
      await analysisService.saveHistory(AiAnalysisHistoryItem(
        id: 'h2',
        timestamp: 200,
        textSnippet: 'S2',
        fullText: 'F2',
        tags: [],
        summary: 'Sum2',
        provider: 'OpenAI',
        model: 'gpt-4o-mini',
      ));

      var list = await analysisService.loadHistory();
      expect(list.length, 2);

      await analysisService.deleteHistoryItem('h1');
      list = await analysisService.loadHistory();
      expect(list.length, 1);
      expect(list.first.id, 'h2');

      await analysisService.clearAllHistory();
      list = await analysisService.loadHistory();
      expect(list, isEmpty);
    });
  });

  group('4. Import from Analysis as Document Tests (FR-C-07, C.8.2)', () {
    test('importFromAnalysis creates Document, PageItem, and triggers repository reactive notification', () async {
      bool notified = false;
      final sub = repository.onDataChanged.listen((_) => notified = true);

      const sampleText = '''臨床診療建議指引第3章
針對第二型糖尿病患者伴隨慢性腎臟病之處置策略。
應考慮優先開立 SGLT2 抑制劑或 GLP-1 類似物。''';

      final tags = [
        TagItem(id: 'imp_1', name: '第二型糖尿病', category: '疾病/症狀', confidence: 0.95),
        TagItem(id: 'imp_2', name: '慢性腎臟病', category: '疾病/症狀', confidence: 0.90),
      ];

      final doc = await analysisService.importFromAnalysis(
        text: sampleText,
        tags: tags,
        summary: '本指南提供糖尿病合併腎病變之處置指引。',
        chineseSummary: '中文重點說明：優先選用SGLT2保護腎功能。',
        customTitle: '糖尿病腎病變指引',
      );

      expect(doc.title, '糖尿病腎病變指引');
      expect(doc.sourceType, 'text');
      expect(doc.tags.length, 2);
      expect(doc.summary, contains('處置指引'));

      // Verify persisted in repository
      final savedDoc = await repository.getDocument(doc.id);
      expect(savedDoc, isNotNull);
      expect(savedDoc!.title, '糖尿病腎病變指引');

      final pages = await repository.getDocumentPages(doc.id);
      expect(pages.length, 1);
      expect(pages.first.ocrText, contains('慢性腎臟病之處置策略'));

      await Future.delayed(const Duration(milliseconds: 50));
      expect(notified, isTrue);

      await sub.cancel();
    });
  });

  group('5. OllamaClient Friendly Error and Custom Prompt Tests (C.11)', () {
    test('Returns clear messages for common API errors', () {
      final e401 = DioException(
        requestOptions: RequestOptions(path: '/test'),
        response: Response(requestOptions: RequestOptions(path: '/test'), statusCode: 401),
      );
      expect(ollamaClient.getFriendlyErrorMessage(e401), contains('API KEY 無效'));

      final e429 = DioException(
        requestOptions: RequestOptions(path: '/test'),
        response: Response(requestOptions: RequestOptions(path: '/test'), statusCode: 429),
      );
      expect(ollamaClient.getFriendlyErrorMessage(e429), contains('API 呼叫額度不足'));

      final eTimeout = DioException(
        requestOptions: RequestOptions(path: '/test'),
        type: DioExceptionType.connectionTimeout,
      );
      expect(ollamaClient.getFriendlyErrorMessage(eTimeout), contains('請求逾時'));

      final eCancel = DioException(
        requestOptions: RequestOptions(path: '/test'),
        type: DioExceptionType.cancel,
      );
      expect(ollamaClient.getFriendlyErrorMessage(eCancel), contains('已取消分析'));
    });

    test('Builds analysis prompt with custom prompt block attached', () {
      const customInstruction = '務必加註 ICD-10 編碼，並強化併發症提取。';
      final prompt = ollamaClient.buildAnalysisPrompt(
        '病人患有嚴重心悸與高血壓。',
        customPrompt: customInstruction,
      );

      expect(prompt, contains('【使用者自訂進階指示】'));
      expect(prompt, contains(customInstruction));
    });
  });

  group('6. AiAnalysisScreen Widget UI Tests (C.7.1, C.7.2)', () {
    testWidgets('Renders input area, word count, buttons, and handles text input', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AiAnalysisScreen(
            repository: repository,
            ollamaClient: ollamaClient,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check title and UI elements
      expect(find.text('AI 分析'), findsOneWidget);
      expect(find.text('Provider：'), findsOneWidget);
      expect(find.text('開始分析'), findsOneWidget);
      expect(find.text('字數：0'), findsOneWidget);

      // Enter text
      final textField = find.byType(TextField).first;
      await tester.enterText(textField, '測試輸入一段醫學文字內容以供 AI 分析。');
      await tester.pump();

      expect(find.text('字數：21'), findsOneWidget);

      // Verify buttons exist
      expect(find.text('貼上'), findsOneWidget);
      expect(find.text('載入檔案'), findsOneWidget);
      expect(find.text('清空'), findsOneWidget);

      // Tap clear
      await tester.tap(find.text('清空'));
      await tester.pump();

      expect(find.text('字數：0'), findsOneWidget);
    });
  });
}
