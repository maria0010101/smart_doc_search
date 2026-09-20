import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:smart_doc_search/data/datasources/koredb_datasource.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('copyToDocuments creates and stores file in Smart_Doc directory', (WidgetTester tester) async {
    final ds = KoreDbNativeDataSource();
    final tempDir = await getTemporaryDirectory();
    final testFile = File('${tempDir.path}/integration_test_doc.txt');
    await testFile.writeAsString('Test literature content for Smart_Doc');

    final copiedPath = await ds.copyToDocuments(testFile.path, 'integration_test_doc.txt');
    expect(copiedPath, isNotNull);
    expect(copiedPath, contains('Smart_Doc'));
    expect(copiedPath, endsWith('integration_test_doc.txt'));

    final copiedFile = File(copiedPath!);
    expect(await copiedFile.exists(), isTrue);
    expect(await copiedFile.readAsString(), 'Test literature content for Smart_Doc');

    // Test openFile with this file
    final openOk = await ds.openFile(copiedPath);
    expect(openOk, isTrue);

    // Clean up
    await testFile.delete();
    if (await copiedFile.exists()) {
      await copiedFile.delete();
    }
  });
}
