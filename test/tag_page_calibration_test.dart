import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_doc_search/core/utils/tag_page_calibrator.dart';
import 'package:smart_doc_search/data/datasources/ollama_client.dart';
import 'package:smart_doc_search/data/models/document_model.dart';

void main() {
  group('TagItem Page Information Tests', () {
    test('TagItem serializes and deserializes pageNumber and pages correctly', () {
      final tag = TagItem(
        id: 't-1',
        name: '第2型糖尿病',
        category: '疾病/症狀',
        confidence: 0.95,
        source: 'ai',
        verified: false,
        pageNumber: 15,
        pages: [15, 16],
      );

      final map = tag.toMap();
      expect(map['page_number'], 15);
      expect(map['pages'], [15, 16]);

      final fromMap = TagItem.fromMap(map);
      expect(fromMap.pageNumber, 15);
      expect(fromMap.pages, [15, 16]);

      final jsonMap = json.decode(tag.toJson()) as Map<String, dynamic>;
      expect(jsonMap['page_number'], 15);
      expect(jsonMap['pages'], [15, 16]);
    });
  });

  group('TagPageCalibrator Tests', () {
    final page1Toc = PageItem(
      id: 'p1',
      documentId: 'doc1',
      pageNumber: 1,
      imagePath: '',
      ocrText: '''
目錄 Table of Contents
第一章 導言與背景 ..................................... 3
第二章 臨床診斷標準 ................................... 8
第三章 第2型糖尿病之治療指引與藥物選擇 ............ 15
第四章 併發症預防與追蹤 ............................... 28
附錄 參考文獻 ......................................... 45
''',
    );

    final page2Intro = PageItem(
      id: 'p2',
      documentId: 'doc1',
      pageNumber: 2,
      imagePath: '',
      ocrText: '本書編撰委員會名單與序言。本指引旨在協助臨床醫師提升診療品質。',
    );

    final page15Diabetes = PageItem(
      id: 'p15',
      documentId: 'doc1',
      pageNumber: 15,
      imagePath: '',
      ocrText: '''
第三章 第2型糖尿病之治療指引與藥物選擇

第2型糖尿病（Type 2 Diabetes Mellitus, T2D）為慢性代謝異常疾病。
首選口服降血糖藥物為 Metformin，每日劑量建議由 500mg 起始。
若糖化血色素（HbA1c）未達標，可考慮合併使用 SGLT-2 抑制劑或 GLP-1 受體促效劑。
對合併心血管疾病之第2型糖尿病患者，應優先選用具器官保護證據之藥物。
''',
      layoutBlocks: [
        LayoutBlock(
          type: 'title',
          text: '第三章 第2型糖尿病之治療指引與藥物選擇',
          bbox: [0, 0, 100, 20],
        ),
      ],
    );

    final pages = [page1Toc, page2Intro, page15Diabetes];

    test('isTableOfContentsPage accurately identifies TOC page', () {
      expect(TagPageCalibrator.isTableOfContentsPage(page1Toc), isTrue);
      expect(TagPageCalibrator.isTableOfContentsPage(page2Intro), isFalse);
      expect(TagPageCalibrator.isTableOfContentsPage(page15Diabetes), isFalse);
    });

    test('extractTocTargetPage extracts target page from TOC index line', () {
      final targetPage = TagPageCalibrator.extractTocTargetPage(
        page1Toc.ocrText,
        '第2型糖尿病',
        50,
      );
      expect(targetPage, equals(15));
    });

    test('findSubstantivePageForKeyword picks substantive page 15 instead of TOC page 1', () {
      final substantivePage = TagPageCalibrator.findSubstantivePageForKeyword(
        '第2型糖尿病',
        pages,
        aiSuggestedPage: 1, // Even if AI mistakenly suggested page 1
      );
      expect(substantivePage, equals(15));
    });

    test('calibrateTags corrects AI suggested page 1 to substantive page 15', () {
      final rawTags = [
        TagItem(
          id: 'raw-1',
          name: '第2型糖尿病',
          category: '疾病/症狀',
          confidence: 0.95,
          source: 'ai',
          pageNumber: 1, // Mistakenly indexed to TOC page 1
        ),
        TagItem(
          id: 'raw-2',
          name: 'Metformin',
          category: '醫學術語',
          confidence: 0.90,
          source: 'ai',
          pageNumber: null,
        ),
      ];

      final calibrated = TagPageCalibrator.calibrateTags(
        tags: rawTags,
        pages: pages,
        title: '糖尿病診療指引',
      );

      final t1 = calibrated.firstWhere((t) => t.name == '第2型糖尿病');
      expect(t1.pageNumber, equals(15));
      expect(t1.pages, contains(15));

      final t2 = calibrated.firstWhere((t) => t.name == 'Metformin');
      expect(t2.pageNumber, equals(15));
      expect(t2.pages, contains(15));
    });

    test('resolveSubstantivePageForSearchHit resolves to page 15 for search queries', () {
      final docTags = [
        TagItem(
          id: 't-1',
          name: '第2型糖尿病',
          category: '疾病/症狀',
          confidence: 0.95,
          source: 'ai',
          pageNumber: 15,
          pages: [15],
        ),
      ];

      // 1. Tag search
      final tagMatchPage = TagPageCalibrator.resolveSubstantivePageForSearchHit(
        searchKeywords: [],
        searchTags: ['第2型糖尿病'],
        docTags: docTags,
        docPages: pages,
        docSummary: '本文獻詳述第2型糖尿病之治療指引 (P.15)',
      );
      expect(tagMatchPage, equals(15));

      // 2. Keyword search
      final kwMatchPage = TagPageCalibrator.resolveSubstantivePageForSearchHit(
        searchKeywords: ['第2型糖尿病'],
        searchTags: [],
        docTags: docTags,
        docPages: pages,
        docSummary: '本文獻詳述第2型糖尿病之治療指引 (P.15)',
      );
      expect(kwMatchPage, equals(15));
    });
  });

  group('OllamaClient Tag Parsing Tests', () {
    test('OllamaClient parses page_number from AI JSON response', () {
      final client = OllamaClient();
      final jsonSample = '''
{
  "summary": "本文件詳細介紹高血壓用藥指引 (P.8)",
  "chinese_summary": "本文件詳細介紹高血壓用藥指引 (P.8)",
  "detected_language": "zh-TW",
  "tags": [
    {
      "name": "高血壓",
      "category": "疾病/症狀",
      "confidence": 0.96,
      "page_number": 8
    },
    {
      "name": "ACEI",
      "category": "醫學術語",
      "confidence": 0.92,
      "page": 8
    }
  ]
}
''';
      final analysis = client.parseAnalysisJson(jsonSample);
      expect(analysis.tags.length, equals(2));
      expect(analysis.tags[0].name, equals('高血壓'));
      expect(analysis.tags[0].pageNumber, equals(8));
      expect(analysis.tags[1].name, equals('ACEI'));
      expect(analysis.tags[1].pageNumber, equals(8));
    });
  });
}
