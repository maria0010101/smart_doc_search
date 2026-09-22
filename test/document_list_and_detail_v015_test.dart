import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_doc_search/data/datasources/koredb_datasource.dart';
import 'package:smart_doc_search/data/datasources/ollama_client.dart';
import 'package:smart_doc_search/data/models/document_model.dart';
import 'package:smart_doc_search/data/repositories/document_repository.dart';
import 'package:smart_doc_search/features/document/document_detail_screen.dart';
import 'package:smart_doc_search/features/document/document_list_screen.dart';
import 'package:smart_doc_search/features/home/home_screen.dart';
import 'package:smart_doc_search/features/import/import_service.dart';

void main() {
  group('v0.1.5 Document List & Targeted Page View Tests', () {
    late KoreDbNativeDataSource koreDb;
    late DocumentRepository repo;
    late OllamaClient ollamaClient;
    late ImportService importService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      koreDb = KoreDbNativeDataSource();
      repo = DocumentRepository(dataSource: koreDb);
      ollamaClient = OllamaClient();
      importService = ImportService(
        repository: repo,
        dataSource: koreDb,
        ollamaClient: ollamaClient,
      );

      // Seed 2 documents
      final doc1 = Document(
        id: 'doc_1',
        title: '心血管臨床用藥手冊',
        sourceType: 'pdf',
        fileHash: 'hash_1',
        filePath: '/docs/doc1.pdf',
        pageCount: 5,
        summary: '這是一份心血管醫學臨床指引，包含第 3 頁劑量表。',
        tags: [TagItem(id: 't1', name: '心血管', category: '醫學術語')],
        createdAt: 1000,
        updatedAt: 1000,
      );
      final doc2 = Document(
        id: 'doc_2',
        title: '糖尿病照護準則',
        sourceType: 'pdf',
        fileHash: 'hash_2',
        filePath: '/docs/doc2.pdf',
        pageCount: 3,
        summary: '糖尿病飲食與胰島素治療原則。',
        tags: [TagItem(id: 't2', name: '糖尿病', category: '疾病/症狀')],
        createdAt: 2000,
        updatedAt: 2000,
      );

      await koreDb.insertDocument(doc1);
      await koreDb.insertDocument(doc2);

      // Add pages to doc1
      for (int i = 1; i <= 5; i++) {
        await koreDb.insertPage(PageItem(
          id: 'p_doc1_$i',
          documentId: 'doc_1',
          pageNumber: i,
          imagePath: '',
          ocrText: '這是心血管手冊第 $i 頁詳細內文。',
        ));
      }
    });

    testWidgets('1. DocumentListScreen renders all documents and supports rename and delete', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocumentListScreen(
              repository: repo,
              ollamaClient: ollamaClient,
              importService: importService,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify list contains seeded documents
      expect(find.text('文獻清單'), findsOneWidget);
      expect(find.text('心血管臨床用藥手冊'), findsWidgets);
      expect(find.text('糖尿病照護準則'), findsWidgets);

      // Verify rename functionality
      expect(find.text('更名'), findsWidgets);
      await tester.tap(find.text('更名').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('修改文獻名稱'), findsOneWidget);
      // Type new title
      final textField = find.byType(TextField).last;
      await tester.enterText(textField, '心血管臨床用藥手冊【最新修訂版】');
      await tester.tap(find.text('確認更名'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify updated title reflected in list
      expect(find.text('心血管臨床用藥手冊【最新修訂版】'), findsWidgets);

      // Verify delete functionality
      final deleteBtn = find.text('刪除').first;
      await tester.tap(deleteBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('刪除確認'), findsOneWidget);
      await tester.tap(find.text('確定刪除'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify count decreased
      final remaining = await repo.getAllDocuments();
      expect(remaining.length, equals(1));
    });

    testWidgets('2. HomeScreen 文獻總數 stat card triggers tab navigation to Tab 1', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      int navigatedTab = -1;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeScreen(
              repository: repo,
              ollamaClient: ollamaClient,
              importService: importService,
              onNavigateTab: (idx) => navigatedTab = idx,
              onQuickSearch: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify 文獻總數 card is rendered
      expect(find.text('文獻總數'), findsOneWidget);

      // Tap 文獻總數 card
      await tester.tap(find.text('文獻總數'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Expect navigation to tab index 1 (文獻分頁)
      expect(navigatedTab, equals(1));
    });

    testWidgets('3. DocumentDetailScreen prioritizes Tab 0 (文獻內容) and focuses on initialPageNumber', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocumentDetailScreen(
              documentId: 'doc_1',
              repository: repo,
              ollamaClient: ollamaClient,
              initialPageNumber: 3, // Search result hit page
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Tab 0 should be "文獻內容", Tab 1 "摘要與標籤", Tab 2 "檔案元數據"
      expect(find.text('文獻內容'), findsOneWidget);
      expect(find.text('摘要與標籤'), findsOneWidget);
      expect(find.text('檔案元數據'), findsOneWidget);

      // Should show the targeted citation banner for page 3
      expect(find.textContaining('已直接呈現第 3 頁內容'), findsOneWidget);
      expect(find.text('第 3 頁 / 共 5 頁'), findsOneWidget);
      expect(find.textContaining('這是心血管手冊第 3 頁詳細內文'), findsOneWidget);

      // Switch to Tab 1 (摘要與標籤)
      await tester.tap(find.text('摘要與標籤'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // AI Summary and Medical Tags should appear in Tab 1
      expect(find.text('AI 智能文獻摘要'), findsOneWidget);
      expect(find.text('專業醫學標籤分類 (按維度)'), findsOneWidget);
    });
  });
}
