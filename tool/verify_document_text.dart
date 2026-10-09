import 'dart:io';

// A socket-free check for environments where Flutter's test server is blocked.
import 'package:smart_doc_search/core/utils/document_text.dart';
import 'package:smart_doc_search/core/utils/tag_page_calibrator.dart';
import 'package:smart_doc_search/data/models/document_model.dart';
import 'package:smart_doc_search/features/search/search_query_parser.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void main() {
  const text =
      'Clinical guidance\n\n慢性阻塞性\r\n肺病與治療。\nHeart\n  failure management improves\npatient care.';
  final body = DocumentText.searchable(text);
  check(
    DocumentText.searchable('慢性\r\n\r\n肺病') == '慢性肺病',
    'CRLF paragraph breaks',
  );
  check(body.contains('慢性阻塞性肺病'), 'Chinese CRLF matching');
  check(body.contains('heart failure management'), 'English phrase matching');
  check(
    DocumentText.searchable('慢性\n\n肺病') == '慢性肺病',
    'Chinese paragraph breaks in search',
  );
  check(
    DocumentText.reflow(text).contains('guidance\n\n慢性'),
    'Reading paragraph preservation',
  );
  check(
    DocumentText.reflow('COVID-19\rIL-6') == 'COVID-19 IL-6',
    'Hyphen preservation',
  );
  check(
    EncodedKeywordSet.fromEncoded(['+heart failure']).matchesGates(body),
    'Required phrase',
  );
  check(
    !EncodedKeywordSet.fromEncoded(['-heart failure']).matchesGates(body),
    'Excluded phrase',
  );
  final pages = [
    PageItem(
      id: 'p1',
      documentId: 'doc',
      pageNumber: 1,
      imagePath: '',
      ocrText: 'Preface',
    ),
    PageItem(
      id: 'p2',
      documentId: 'doc',
      pageNumber: 2,
      imagePath: '',
      ocrText: text,
    ),
  ];
  for (final keyword in ['慢性阻塞性肺病', 'heart failure']) {
    check(
      TagPageCalibrator.findSubstantivePageForKeyword(keyword, pages) == 2,
      'Page location: $keyword',
    );
  }
  stdout.writeln(
    'PASS: normalization, paragraphs, AND/NOT gates and wrapped-phrase page location',
  );
}
