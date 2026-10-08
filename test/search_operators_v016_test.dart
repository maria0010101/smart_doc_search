import 'package:flutter_test/flutter_test.dart';
import 'package:smart_doc_search/data/datasources/koredb_datasource.dart';
import 'package:smart_doc_search/data/datasources/ollama_client.dart';
import 'package:smart_doc_search/data/models/document_model.dart';
import 'package:smart_doc_search/features/search/hybrid_search_service.dart';
import 'package:smart_doc_search/features/search/search_query_parser.dart';

void main() {
  group('SearchQueryParser operators', () {
    test('splits required, optional and excluded groups', () {
      final parsed = SearchQueryParser.parse('糖尿病+心血管 -動物實驗 治療');
      expect(parsed.required, ['糖尿病', '心血管']);
      expect(parsed.excluded, ['動物實驗']);
      expect(parsed.optional, ['治療']);
      expect(parsed.hasOperators, isTrue);
      expect(parsed.positiveKeywords, ['糖尿病', '心血管', '治療']);
      expect(parsed.toEncodedKeywords(), ['+糖尿病', '+心血管', '治療', '-動物實驗']);
    });

    test('a leading + marks a single required keyword', () {
      final parsed = SearchQueryParser.parse('+糖尿病 心臟');
      expect(parsed.required, ['糖尿病']);
      expect(parsed.optional, ['心臟']);
    });

    test('hyphenated terms are preserved as single keywords', () {
      final parsed = SearchQueryParser.parse('COVID-19 IL-6 T-cell');
      expect(parsed.optional, ['COVID-19', 'IL-6', 'T-cell']);
      expect(parsed.excluded, isEmpty);
    });

    test('a hyphen between Han characters acts as the exclusion operator', () {
      final parsed = SearchQueryParser.parse('糖尿病-高血壓');
      expect(parsed.optional, ['糖尿病']);
      expect(parsed.excluded, ['高血壓']);
    });

    test('exclusion wins when a term appears in both groups', () {
      final parsed = SearchQueryParser.parse('+流感 -流感');
      expect(parsed.excluded, ['流感']);
      expect(parsed.required, isEmpty);
      expect(parsed.optional, isEmpty);
    });

    test('requireAll promotes plain keywords to required (AND mode)', () {
      final parsed = SearchQueryParser.parse('糖尿病 心血管 腎病變', requireAll: true);
      expect(parsed.required, ['糖尿病', '心血管', '腎病變']);
      expect(parsed.optional, isEmpty);
      // Explicit operators still take precedence over the mode.
      final withOps = SearchQueryParser.parse('糖尿病 -動物 +指引', requireAll: true);
      expect(withOps.required, ['糖尿病', '指引']);
      expect(withOps.excluded, ['動物']);
    });

    test('full-width separators split keywords', () {
      final parsed = SearchQueryParser.parse('糖尿病、心血管，腎病變；飲食');
      expect(parsed.optional, ['糖尿病', '心血管', '腎病變', '飲食']);
    });

    test('EncodedKeywordSet decodes prefixes and enforces gates', () {
      final set = EncodedKeywordSet.fromEncoded(['+A', 'B', '-C']);
      expect(set.required, ['A']);
      expect(set.optional, ['B']);
      expect(set.excluded, ['C']);
      expect(set.positive, ['A', 'B']);
      expect(set.matchesGates('a b'), isTrue);
      expect(set.matchesGates('b c'), isFalse, reason: 'missing required A');
      expect(set.matchesGates('a b c'), isFalse, reason: 'contains excluded C');
    });
  });

  group('HybridSearchService operator semantics', () {
    late KoreDbNativeDataSource dataSource;
    late HybridSearchService service;

    Document buildDoc(String id, String title, String summary) {
      return Document(
        id: id,
        title: title,
        sourceType: 'pdf',
        filePath: '/docs/$id.pdf',
        fileHash: 'hash_$id',
        pageCount: 1,
        summary: summary,
        tags: [TagItem(id: '${id}_t', name: '主題標籤', category: '主題')],
        language: 'zh-TW',
        createdAt: 100,
        updatedAt: 100,
      );
    }

    setUp(() async {
      dataSource = KoreDbNativeDataSource();
      service = HybridSearchService(
        dataSource: dataSource,
        ollamaClient: OllamaClient(),
      );

      await dataSource.insertDocument(
        buildDoc('d1', '糖尿病與心血管研究', '第2型糖尿病合併心血管疾病之治療策略'),
      );
      await dataSource.insertDocument(
        buildDoc('d2', '糖尿病動物實驗', '糖尿病小鼠模式之動物實驗結果'),
      );
      await dataSource.insertDocument(
        buildDoc('d3', '高血壓治療指引', '原發性高血壓的用藥建議'),
      );
    });

    test('+ requires every joined keyword to be present', () async {
      final result = await service.executeSearch(
        queryText: '糖尿病+心血管',
        enableSemanticSearch: false,
      );
      expect(result.items.map((hit) => hit.document.id).toList(), ['d1']);
    });

    test('- removes documents that contain the excluded keyword', () async {
      final result = await service.executeSearch(
        queryText: '糖尿病 -動物',
        enableSemanticSearch: false,
      );
      expect(result.items.map((hit) => hit.document.id).toList(), ['d1']);
    });

    test('space separated keywords remain optional (OR ranking)', () async {
      final result = await service.executeSearch(
        queryText: '高血壓 動物',
        enableSemanticSearch: false,
      );
      expect(result.items.map((hit) => hit.document.id).toSet(), {'d2', 'd3'});
    });

    test('an empty query returns every document', () async {
      final result = await service.executeSearch(
        queryText: '',
        enableSemanticSearch: false,
      );
      expect(result.items.length, 3);
    });

    test('全部符合 (AND) mode requires every keyword to be present', () async {
      final result = await service.executeSearch(
        queryText: '糖尿病 心血管',
        requireAllKeywords: true,
        enableSemanticSearch: false,
      );
      expect(result.items.map((hit) => hit.document.id).toList(), ['d1']);
    });

    test('全部符合 (AND) mode still honours the - exclusion operator', () async {
      final result = await service.executeSearch(
        queryText: '糖尿病 -心血管',
        requireAllKeywords: true,
        enableSemanticSearch: false,
      );
      expect(result.items.map((hit) => hit.document.id).toList(), ['d2']);
    });
  });
}
