import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_doc_search/core/constants/app_constants.dart';
import 'package:smart_doc_search/data/datasources/koredb_datasource.dart';
import 'package:smart_doc_search/data/datasources/ollama_client.dart';
import 'package:smart_doc_search/data/datasources/sqlite_desktop_datasource.dart';
import 'package:smart_doc_search/data/models/document_model.dart';
import 'package:smart_doc_search/data/repositories/document_repository.dart';
import 'package:smart_doc_search/features/search/hybrid_search_service.dart';
import 'package:smart_doc_search/features/search/search_screen.dart';
import 'package:smart_doc_search/features/settings/settings_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('1. DocumentHit & Page Number Serialization Tests', () {
    test('DocumentHit preserves pageNumber in toMap and fromMap', () {
      final doc = Document(
        id: 'doc_test_1',
        title: '心肌梗塞文獻',
        sourceType: 'pdf',
        fileHash: 'hash123',
        filePath: '/storage/docs/doc1.pdf',
        pageCount: 15,
        summary: '這是一份心臟病文獻摘要 (P.3)',
        tags: [TagItem(id: '1', name: 'AMI', category: 'disease')],
        createdAt: 1600000000000,
        updatedAt: 1600000000000,
      );

      final hit = DocumentHit(
        document: doc,
        score: 0.95,
        highlight: '急性心肌梗塞診斷指引...',
        matchedTags: ['AMI'],
        pageNumber: 3,
      );

      final map = hit.toMap();
      expect(map['pageNumber'], equals(3));

      final restored = DocumentHit.fromMap(map);
      expect(restored.document.id, equals('doc_test_1'));
      expect(restored.score, equals(0.95));
      expect(restored.pageNumber, equals(3));
      expect(restored.highlight, contains('急性心肌梗塞'));
    });
  });

  group('2. KoreDb & SQLite Literature Path & Search Tests', () {
    late Directory tempDir;
    late KoreDbNativeDataSource koreDb;
    late SqliteDesktopDataSource sqliteDb;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('smart_doc_path_test_');
      SharedPreferences.setMockInitialValues({});
      koreDb = KoreDbNativeDataSource();
      sqliteDb = SqliteDesktopDataSource(customDbPath: p.join(tempDir.path, 'test_search.db'));
    });

    tearDown(() async {
      await sqliteDb.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('KoreDbNativeDataSource copyToDocuments supports customTargetDir', () async {
      final dummySource = File(p.join(tempDir.path, 'dummy_source.pdf'));
      await dummySource.writeAsString('Dummy PDF content');

      final customDir = Directory(p.join(tempDir.path, 'MyCustomStorage'));
      final copied = await koreDb.copyToDocuments(dummySource.path, 'copied_literature.pdf', customTargetDir: customDir.path);

      expect(copied, isNotNull);
      expect(File(copied!).existsSync(), isTrue);
      expect(p.dirname(copied), equals(customDir.path));
    });

    test('SqliteDesktopDataSource copyToDocuments supports customTargetDir', () async {
      final dummySource = File(p.join(tempDir.path, 'dummy_desktop.pdf'));
      await dummySource.writeAsString('Desktop PDF content');

      final customDir = Directory(p.join(tempDir.path, 'DesktopCustomStorage'));
      final copied = await sqliteDb.copyToDocuments(dummySource.path, 'desktop_copied.pdf', customTargetDir: customDir.path);

      expect(copied, isNotNull);
      expect(File(copied!).existsSync(), isTrue);
      expect(p.dirname(copied), equals(customDir.path));
    });

    test('SqliteDesktopDataSource hybridSearch attributes matched pageNumber', () async {
      final doc = Document(
        id: 'doc_multi_page',
        title: '臨床指引文件',
        sourceType: 'pdf',
        fileHash: 'hash_mp',
        filePath: '/docs/doc_mp.pdf',
        pageCount: 3,
        summary: '綜合醫學評估報告',
        tags: [TagItem(id: 't1', name: '臨床', category: 'general')],
        createdAt: 1000,
        updatedAt: 1000,
      );
      await sqliteDb.insertDocument(doc);

      // Page 1: Introduction
      await sqliteDb.insertPage(PageItem(
        id: 'p1',
        documentId: doc.id,
        pageNumber: 1,
        imagePath: '',
        ocrText: '這是引言章節，介紹健康與生活方式。',
      ));

      // Page 2: Contains target keyword '抗凝血劑'
      await sqliteDb.insertPage(PageItem(
        id: 'p2',
        documentId: doc.id,
        pageNumber: 2,
        imagePath: '',
        ocrText: '第二章詳細敘述新型抗凝血劑 (NOAC) 之劑量使用準則。',
      ));

      // Search keyword '抗凝血劑'
      final result = await sqliteDb.hybridSearch(keywords: ['抗凝血劑']);
      expect(result.items.isNotEmpty, isTrue);
      final hit = result.items.first;
      expect(hit.document.id, equals('doc_multi_page'));
      expect(hit.pageNumber, equals(2));
      expect(hit.highlight, contains('抗凝血劑'));
    });

    test('DocumentRepository effective literature directory respects SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final repo = DocumentRepository(dataSource: sqliteDb);

      final defaultDir = await repo.getDefaultLiteratureDirectory();
      expect(defaultDir, contains('Smart_Doc'));

      final effective1 = await repo.getEffectiveLiteratureDirectory();
      expect(effective1, equals(defaultDir));

      // Set user custom storage path in SharedPreferences
      final customTestPath = p.join(tempDir.path, 'UserSelectedDir');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppConstants.prefLiteratureStoragePath, customTestPath);

      final effective2 = await repo.getEffectiveLiteratureDirectory();
      expect(effective2, equals(customTestPath));
    });
  });

  group('3. SearchScreen & SettingsScreen Widget UI Tests', () {
    late KoreDbNativeDataSource koreDb;
    late DocumentRepository repo;
    late OllamaClient ollamaClient;
    late HybridSearchService searchService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        AppConstants.prefAiProvider: 'ollama',
      });
      koreDb = KoreDbNativeDataSource();
      repo = DocumentRepository(dataSource: koreDb);
      ollamaClient = OllamaClient();
      searchService = HybridSearchService(dataSource: koreDb, ollamaClient: ollamaClient);

      // Seed a test document
      final doc = Document(
        id: 'ui_doc_1',
        title: '心房顫動最新診療指引',
        sourceType: 'pdf',
        fileHash: 'hash_af',
        filePath: '/dummy/path.pdf',
        pageCount: 12,
        summary: '本指南詳述心房顫動之抗凝治療與心律控制原則，包含藥物選擇、禁忌症及第 4 頁劑量調整表。',
        tags: [TagItem(id: 't1', name: '心房顫動', category: 'disease')],
        createdAt: DateTime.now().millisecondsSinceEpoch,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await koreDb.insertDocument(doc);
      await koreDb.insertPage(PageItem(
        id: 'ui_p4',
        documentId: doc.id,
        pageNumber: 4,
        imagePath: '',
        ocrText: '第 4 頁劑量調整表：依腎功能 CrCl 調整抗凝劑用量。',
      ));
    });

    testWidgets('SearchScreen renders page badge and literature summary', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchScreen(
              repository: repo,
              ollamaClient: ollamaClient,
              searchService: searchService,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Initial search results rendered
      expect(find.text('心房顫動最新診療指引'), findsOneWidget);
      expect(find.text('文獻摘要內容'), findsOneWidget);
      expect(find.textContaining('本指南詳述心房顫動之抗凝治療'), findsOneWidget);
      // Page number resolved from summary citation "第 4 頁" or hit
      expect(find.text('第 4 頁'), findsWidgets);
    });

    testWidgets('SettingsScreen renders Literature Storage Path card and actions', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1000));

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            repository: repo,
            ollamaClient: ollamaClient,
            onThemeChanged: (_) {},
            isDarkMode: false,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify Literature Storage Path card
      expect(find.text('文獻原始檔存檔路徑設定'), findsOneWidget);
      expect(find.text('系統預設'), findsOneWidget);
      expect(find.text('選擇資料夾'), findsOneWidget);
      expect(find.text('手動輸入路徑'), findsOneWidget);
      expect(find.textContaining('Smart_Doc'), findsOneWidget);

      // Tap manual input button to verify input dialog
      await tester.tap(find.text('手動輸入路徑'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('手動指定文獻存檔路徑'), findsOneWidget);
      expect(find.text('請輸入或貼上本機資料夾之絕對路徑：'), findsOneWidget);
      expect(find.text('確認儲存'), findsOneWidget);

      // Cancel dialog
      await tester.tap(find.text('取消'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });
  });
}
