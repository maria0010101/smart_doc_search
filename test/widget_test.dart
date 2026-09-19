import 'package:flutter_test/flutter_test.dart';
import 'package:smart_doc_search/data/datasources/koredb_datasource.dart';
import 'package:smart_doc_search/data/datasources/ollama_client.dart';
import 'package:smart_doc_search/data/repositories/document_repository.dart';
import 'package:smart_doc_search/features/import/import_service.dart';
import 'package:smart_doc_search/features/search/hybrid_search_service.dart';
import 'package:smart_doc_search/main.dart';

void main() {
  testWidgets('SmartDocSearchApp smoke test and navigation verify', (WidgetTester tester) async {
    final dataSource = KoreDbNativeDataSource();
    final repository = DocumentRepository(dataSource: dataSource);
    final ollamaClient = OllamaClient();
    final importService = ImportService(
      repository: repository,
      dataSource: dataSource,
      ollamaClient: ollamaClient,
    );
    final searchService = HybridSearchService(
      dataSource: dataSource,
      ollamaClient: ollamaClient,
    );

    await tester.pumpWidget(SmartDocSearchApp(
      repository: repository,
      ollamaClient: ollamaClient,
      importService: importService,
      searchService: searchService,
      initialDarkMode: false,
    ));

    await tester.pumpAndSettle();

    // Verify app title & navigation destinations
    expect(find.text('個人智能文獻檢索'), findsOneWidget);
    expect(find.text('首頁'), findsOneWidget);
    expect(find.text('檢索'), findsOneWidget);
    expect(find.text('匯入'), findsNWidgets(2)); // Button on HomeScreen + Bottom NavigationDestination
    expect(find.text('標籤'), findsOneWidget);
    expect(find.text('設定'), findsOneWidget);

    // Tap on Settings tab
    await tester.tap(find.text('設定'));
    await tester.pumpAndSettle();

    // Verify AI Settings Card exists
    expect(find.text('AI 推理服務設定'), findsOneWidget);
    expect(find.text('選擇 AI 服務提供商 (Provider)'), findsOneWidget);
    expect(find.text('連線測試'), findsOneWidget);
  });
}
