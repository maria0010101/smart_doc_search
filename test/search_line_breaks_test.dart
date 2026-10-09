import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_doc_search/core/utils/document_text.dart';
import 'package:smart_doc_search/data/datasources/koredb_datasource.dart';
import 'package:smart_doc_search/data/datasources/sqlite_desktop_datasource.dart';
import 'package:smart_doc_search/data/datasources/ollama_client.dart';

import 'support/wrapped_document_fixture.dart';

import 'package:smart_doc_search/data/repositories/document_repository.dart';
import 'package:smart_doc_search/features/document/document_detail_screen.dart';
import 'package:smart_doc_search/features/document/document_list_screen.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'Reflow preserves paragraphs, joins Chinese and spaces English words',
    () {
      expect(DocumentText.reflow(extracted), contains('guidance\n\n慢性阻塞性肺病'));
      expect(
        DocumentText.searchable(extracted),
        contains('heart failure management'),
      );
      expect(DocumentText.reflow('COVID-19\rIL-6'), 'COVID-19 IL-6');
      expect(DocumentText.searchable('慢性\r\n\r\n肺病'), '慢性肺病');
    },
  );

  for (final engine in ['fallback', 'sqlite']) {
    test(
      '$engine finds wrapped phrases, excludes them and locates the actual page',
      () async {
        final temp = await Directory.systemTemp.createTemp('search-wrap-');
        final KoreDbDataSource source = engine == 'sqlite'
            ? SqliteDesktopDataSource(customDbPath: '${temp.path}/test.db')
            : KoreDbNativeDataSource();
        try {
          await seed(source);
          for (final phrase in ['慢性阻塞性肺病', 'heart failure']) {
            final hit = await source.hybridSearch(keywords: ['+$phrase']);
            expect(hit.total, 1);
            expect(hit.items.single.pageNumber, 2);
            expect(hit.items.single.highlight!.toLowerCase(), contains(phrase));
            expect(
              (await source.hybridSearch(keywords: ['-$phrase'])).total,
              0,
            );
          }
          if (source is SqliteDesktopDataSource) {
            // Simulate an index saved by v0.1.8 and an application restart.
            final db = await source.database;
            await db.update('doc_index', {'body': extracted.toLowerCase()});
            await source.close();
            final reopened = SqliteDesktopDataSource(
              customDbPath: '${temp.path}/test.db',
            );
            try {
              expect(
                (await reopened.hybridSearch(keywords: ['+慢性阻塞性肺病'])).total,
                1,
              );
            } finally {
              await reopened.close();
            }
          }
        } finally {
          if (source is SqliteDesktopDataSource) await source.close();
          await temp.delete(recursive: true);
        }
      },
    );
  }

  testWidgets('Document list finds a phrase present only in wrapped OCR', (
    tester,
  ) async {
    final source = KoreDbNativeDataSource();
    await seed(source);
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DocumentListScreen(
            repository: DocumentRepository(dataSource: source),
            ollamaClient: OllamaClient(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '慢性阻塞性肺病');
    await tester.pumpAndSettle();
    expect(find.text('OCR 文獻'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'heart failure');
    await tester.pumpAndSettle();
    expect(find.text('OCR 文獻'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'missing phrase');
    await tester.pumpAndSettle();
    expect(find.text('OCR 文獻'), findsNothing);
  });

  testWidgets(
    'Full text expands on resize and searches across extracted lines',
    (tester) async {
      final source = KoreDbNativeDataSource();
      await seed(source);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      await tester.pumpWidget(
        MaterialApp(
          home: DocumentDetailScreen(
            documentId: 'wrap',
            initialPageNumber: 2,
            repository: DocumentRepository(dataSource: source),
            ollamaClient: OllamaClient(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final text = find.byType(SelectableText).first;
      final narrowWidth = tester.getSize(text).width;
      expect(
        tester.widget<SelectableText>(text).textSpan!.toPlainText(),
        contains('Heart failure'),
      );
      await tester.binding.setSurfaceSize(const Size(1400, 1200));
      await tester.pumpAndSettle();
      expect(tester.getSize(text).width, greaterThan(narrowWidth + 500));
      expect(tester.getSize(text).width, greaterThan(1200));
      await tester.enterText(find.byType(TextField).first, 'heart failure');
      await tester.pumpAndSettle();
      expect(find.textContaining('共 1 處'), findsOneWidget);
      final spans = tester.widget<SelectableText>(text).textSpan!.children!;
      expect(
        spans.whereType<TextSpan>().any(
          (s) => s.text == 'Heart failure' && s.style?.backgroundColor != null,
        ),
        isTrue,
      );
      expect((await source.getPages('wrap')).last.ocrText, extracted);
    },
  );
}
