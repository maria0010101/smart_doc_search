// Socket-free smoke checks: compile with `flutter build bundle --no-pub
// --target tool/verify_flutter_changes.dart`, then run kernel_blob.bin with
// Flutter's flutter_tester --disable-vm-service.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_doc_search/data/datasources/koredb_datasource.dart';
import 'package:smart_doc_search/data/datasources/sqlite_desktop_datasource.dart';
import 'package:smart_doc_search/data/datasources/ollama_client.dart';
import 'package:smart_doc_search/data/repositories/document_repository.dart';
import 'package:smart_doc_search/features/document/document_detail_screen.dart';
import 'package:smart_doc_search/features/document/document_list_screen.dart';

import '../test/support/wrapped_document_fixture.dart' show seed, extracted;

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Iterable<Element> descendants(Element element) sync* {
  yield element;
  final children = <Element>[];
  element.visitChildren(children.add);
  for (final child in children) {
    yield* descendants(child);
  }
}

Future<void> frame() async {
  await Future<void>.delayed(const Duration(milliseconds: 100));
  WidgetsBinding.instance.handleBeginFrame(null);
  WidgetsBinding.instance.handleDrawFrame();
}

Future<void> show(Widget child, double width) async {
  runApp(
    Directionality(
      textDirection: TextDirection.ltr,
      child: OverflowBox(
        minWidth: width,
        maxWidth: width,
        minHeight: 1200,
        maxHeight: 1200,
        child: SizedBox(
          width: width,
          height: 1200,
          child: MaterialApp(home: Scaffold(body: child)),
        ),
      ),
    ),
  );
  await frame();
  await frame();
  await frame();
}

List<Element> elements() =>
    descendants(WidgetsBinding.instance.rootElement!).toList();
SelectableText textWidget() =>
    elements().map((e) => e.widget).whereType<SelectableText>().first;
double textWidth() =>
    (elements().firstWhere((e) => e.widget is SelectableText).findRenderObject()
            as RenderBox)
        .size
        .width;
bool hasTitle() => elements()
    .map((e) => e.widget)
    .whereType<Text>()
    .any((w) => w.data == 'OCR 文獻');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  Object? renderError;
  FlutterError.onError = (details) {
    renderError = details.exception;
    stderr.writeln(details);
  };
  try {
    for (final engine in ['fallback', 'sqlite']) {
      final temp = await Directory.systemTemp.createTemp('verify-wrap-');
      final KoreDbDataSource source = engine == 'sqlite'
          ? SqliteDesktopDataSource(customDbPath: '${temp.path}/test.db')
          : KoreDbNativeDataSource();
      try {
        await seed(source);
        for (final phrase in ['慢性阻塞性肺病', 'heart failure']) {
          final hit = await source.hybridSearch(keywords: ['+$phrase']);
          check(hit.total == 1, '$engine phrase matching: $phrase');
          check(
            hit.items.single.pageNumber == 2,
            '$engine page location: $phrase',
          );
          check(
            hit.items.single.highlight!.toLowerCase().contains(phrase),
            '$engine snippet',
          );
          check(
            (await source.hybridSearch(keywords: ['-$phrase'])).total == 0,
            '$engine exclusion',
          );
        }
        if (source is SqliteDesktopDataSource) {
          final db = await source.database;
          await db.update('doc_index', {'body': extracted.toLowerCase()});
          await source.close();
          final reopened = SqliteDesktopDataSource(
            customDbPath: '${temp.path}/test.db',
          );
          check(
            (await reopened.hybridSearch(keywords: ['+慢性阻塞性肺病'])).total == 1,
            'Legacy SQLite cache',
          );
          await reopened.close();
        }
      } finally {
        if (source is SqliteDesktopDataSource) await source.close();
        await temp.delete(recursive: true);
      }
    }
    final source = KoreDbNativeDataSource();
    await seed(source);
    final repo = DocumentRepository(dataSource: source);
    final client = OllamaClient();
    final detail = DocumentDetailScreen(
      documentId: 'wrap',
      initialPageNumber: 2,
      repository: repo,
      ollamaClient: client,
    );
    await show(detail, 800);
    final narrow = textWidth();
    check(
      textWidget().textSpan!.toPlainText().contains('Heart failure'),
      'Full text reflow',
    );
    await show(detail, 1400);
    check(
      textWidth() > narrow + 500 && textWidth() > 1200,
      'Full text width resize',
    );
    final search = elements().map((e) => e.widget).whereType<TextField>().first;
    search.controller!.text = 'heart failure';
    search.onChanged?.call('heart failure');
    await frame();
    check(
      textWidget().textSpan!.children!.whereType<TextSpan>().any(
        (s) => s.text == 'Heart failure' && s.style?.backgroundColor != null,
      ),
      'Phrase highlighting',
    );
    check(
      (await source.getPages('wrap')).last.ocrText == extracted,
      'Stored OCR preserved',
    );
    await show(DocumentListScreen(repository: repo, ollamaClient: client), 400);
    for (final phrase in ['慢性阻塞性肺病', 'heart failure', 'missing phrase']) {
      final filter = elements()
          .map((e) => e.widget)
          .whereType<TextField>()
          .first;
      filter.controller!.text = phrase;
      filter.onChanged?.call(phrase);
      await frame();
      check(
        hasTitle() == (phrase != 'missing phrase'),
        'Document list OCR search: $phrase',
      );
    }
    check(renderError == null, 'Flutter render error: $renderError');
    stdout.writeln(
      'PASS: both search engines, legacy SQLite cache, responsive full text, phrase highlighting and list OCR filtering',
    );
    exit(0);
  } catch (error, stack) {
    stderr.writeln('$error\n$stack');
    exit(1);
  }
}
