import 'package:smart_doc_search/data/datasources/koredb_datasource.dart';
import 'package:smart_doc_search/data/models/document_model.dart';

const extracted =
    'Clinical guidance\n\n慢性阻塞性\r\n肺病與治療。\nHeart\n  failure management improves\npatient care.';
Document document() => Document(
  id: 'wrap',
  title: 'OCR 文獻',
  sourceType: 'pdf',
  fileHash: 'wrap',
  filePath: '',
  pageCount: 2,
  createdAt: 1,
  updatedAt: 1,
);
Future<void> seed(KoreDbDataSource source) async {
  await source.insertDocument(document());
  await source.insertPage(
    PageItem(
      id: 'first',
      documentId: 'wrap',
      pageNumber: 1,
      imagePath: '',
      ocrText: 'Preface',
    ),
  );
  await source.insertPage(
    PageItem(
      id: 'second',
      documentId: 'wrap',
      pageNumber: 2,
      imagePath: '',
      ocrText: extracted,
    ),
  );
}
