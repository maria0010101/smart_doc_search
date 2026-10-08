import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_doc_search/core/services/knowledge_graph_service.dart';
import 'package:smart_doc_search/core/utils/document_extraction_util.dart';
import 'package:smart_doc_search/data/datasources/ollama_client.dart';
import 'package:smart_doc_search/data/models/document_model.dart';
import 'package:smart_doc_search/features/graph/widgets/knowledge_graph_view.dart';

void main() {
  group('1. RapidDoc 臨床數據與疾病分類擷取測試', () {
    test('正規表達式與啟發式能精準擷取 ICD-10-CM、ICD-10-PCS 與臨床檢驗值', () {
      const sampleClinicalText = '''
Title: 臨床糖尿病併發症診斷報告
病患主訴多年多渴多尿，臨床診斷為第2型糖尿病 (E11.9)，合併慢性缺血性心臟病 (I25.1) 及本態性高血壓 (I10)。
近期血液檢驗數值顯示：
HbA1c: 8.5 %
BP: 145/92 mmHg
eGFR: 65.4 mL/min/1.73m²
處置方案：安排心導管檢查與冠狀動脈氣球擴張術，執行手術處置碼 02703ZZ。
處方 SGLT2抑制劑處方 強化器官保護。
''';

      final findings = DocumentExtractionUtil.extractClinicalFindings(sampleClinicalText);

      expect(findings.isEmpty, isFalse);
      expect(findings.principalDiagnosis, isNotNull);
      expect(findings.secondaryDiagnoses, contains('第2型糖尿病'));

      // 驗證 ICD 代碼抽取
      final icdCodes = findings.icdCodes.map((c) => c.code).toList();
      expect(icdCodes, contains('E11.9'));
      expect(icdCodes, contains('I25.1'));
      expect(icdCodes, contains('I10'));
      expect(icdCodes, contains('02703ZZ')); // ICD-10-PCS 7碼

      // 驗證檢驗數值抽取
      final labNames = findings.labValues.map((l) => l.testName).toList();
      expect(labNames.any((n) => n.contains('HbA1c')), isTrue);
      expect(labNames.any((n) => n.contains('血壓')), isTrue);
      expect(labNames.any((n) => n.contains('eGFR')), isTrue);

      final hbLab = findings.labValues.firstWhere((l) => l.testName.contains('HbA1c'));
      expect(hbLab.value, contains('8.5'));
    });
  });

  group('2. GraphifyPDF 學術元數據抽取測試', () {
    test('端側能精確抽取 DOI、年份、作者與期刊來源', () {
      const sampleAcademicText = '''
The Lancet Diabetes & Endocrinology 2024; 12(3): 145-159.
DOI: 10.1016/S2213-8587(23)00341-2
PMID: 38245120
Authors: Dr. Alice Smith, Dr. Robert Johnson, Dr. Chen Wei
By: Global Cardiovascular Collaborative
Article: Management of Cardiovascular Risks in Type 2 Diabetes
''';

      final academic = DocumentExtractionUtil.extractAcademicMetadata(sampleAcademicText);

      expect(academic.isEmpty, isFalse);
      expect(academic.doi, equals('10.1016/S2213-8587(23)00341-2'));
      expect(academic.publicationYear, equals(2024));
      expect(academic.journal, contains('The Lancet'));
      expect(academic.citations.any((c) => c.contains('38245120')), isTrue);
      expect(academic.authors, isNotEmpty);
    });
  });

  group('3. llm-knowledge-graph 三元組與知識圖譜構建測試', () {
    test('啟發式能抽取實體關係三元組', () {
      const text = '''
第2型糖尿病可引發冠狀動脈疾病。
SGLT2抑制劑用於治療第2型糖尿病。
糖化血色素反映出長期血糖控制。
''';

      final triplets = DocumentExtractionUtil.extractKnowledgeTriplets(text);
      expect(triplets, isNotEmpty);
      expect(triplets.any((t) => t.subject == '第2型糖尿病' && t.object == '冠狀動脈疾病'), isTrue);
      expect(triplets.any((t) => t.subject == 'SGLT2抑制劑' && t.object == '第2型糖尿病'), isTrue);
    });

    test('OllamaClient 結構化 JSON 能完整解析臨床實體、學術元數據與三元組', () {
      const rawAiJson = '''
{
  "detected_language": "zh-TW",
  "summary": "• 【背景與目的】(P.1) 探討糖尿病與心血管風險之綜合處置。\\n• 【研究結果】(P.2) SGLT2抑制劑顯著改善心衰竭住院率。",
  "chinese_summary": "• 【中文重點】(P.1) 本文獻探討糖尿病合併症處置指引。",
  "medical_terms": ["SGLT2抑制劑", "胰島素阻抗"],
  "diseases_and_symptoms": ["第2型糖尿病", "冠狀動脈心臟病"],
  "classification_codes": ["E11.9", "I25.1"],
  "academic_metadata": {
    "authors": ["王小明", "李大華"],
    "doi": "10.1000/diabetes-cardio-2024",
    "publication_year": 2024,
    "journal": "台灣醫學雜誌",
    "citations": ["ADA Guidelines 2024"],
    "keywords": ["糖尿病", "心臟病"]
  },
  "clinical_findings": {
    "principal_diagnosis": "第2型糖尿病",
    "secondary_diagnoses": ["冠狀動脈心臟病", "高血壓"],
    "procedures": ["心導管檢查", "藥物處方"],
    "lab_values": [
      {"test_name": "HbA1c", "value": "7.1", "unit": "%", "reference_range": "<7.0%"}
    ],
    "icd_codes": [
      {"code": "E11.9", "title": "第2型糖尿病，無併發症", "system": "ICD-10-CM"},
      {"code": "I25.1", "title": "慢性缺血性心臟病", "system": "ICD-10-CM"}
    ]
  },
  "knowledge_triplets": [
    {"subject": "第2型糖尿病", "predicate": "引發併發症", "object": "冠狀動脈心臟病"},
    {"subject": "SGLT2抑制劑", "predicate": "降低住院率於", "object": "心臟衰竭"}
  ],
  "tags": [
    {"name": "E11.9", "category": "疾病分類編碼", "code_system": "ICD-10-CM", "confidence": 0.98, "page_number": 2},
    {"name": "第2型糖尿病", "category": "疾病/症狀", "confidence": 0.95, "page_number": 1}
  ]
}
''';

      final client = OllamaClient();
      final result = client.parseAnalysisJson(rawAiJson);

      expect(result.summary, contains('SGLT2抑制劑'));
      expect(result.tags, isNotEmpty);
      expect(result.academicMetadata, isNotNull);
      expect(result.academicMetadata!.doi, equals('10.1000/diabetes-cardio-2024'));
      expect(result.clinicalFinding, isNotNull);
      expect(result.clinicalFinding!.principalDiagnosis, equals('第2型糖尿病'));
      expect(result.clinicalFinding!.icdCodes.length, greaterThanOrEqualTo(2));
      expect(result.knowledgeTriplets.length, equals(2));
    });
  });

  group('4. KnowledgeGraphService 跨文獻關聯與圖譜計算測試', () {
    final docA = Document(
      id: 'doc_a',
      title: '文獻A：糖尿病心血管併發症研究',
      sourceType: 'pdf',
      filePath: '/path/a.pdf',
      fileHash: 'hash_a',
      createdAt: 1000,
      updatedAt: 1000,
      pageCount: 5,
      tags: [
        TagItem(id: 't1', name: '第2型糖尿病', category: '疾病/症狀', confidence: 0.95),
        TagItem(id: 't2', name: 'E11.9', category: '疾病分類編碼', codeSystem: 'ICD-10-CM', confidence: 0.98),
        TagItem(id: 't3', name: 'SGLT2抑制劑', category: '醫學術語', confidence: 0.90),
      ],
      metadata: {
        'clinical_findings': {
          'principal_diagnosis': '第2型糖尿病',
          'icd_codes': [
            {'code': 'E11.9', 'title': '第2型糖尿病', 'system': 'ICD-10-CM'}
          ]
        },
        'knowledge_triplets': [
          {'subject': '第2型糖尿病', 'predicate': '導致', 'object': '心血管疾病'}
        ]
      },
    );

    final docB = Document(
      id: 'doc_b',
      title: '文獻B：SGLT2抑制劑在慢性腎病與心衰竭之臨床實證',
      sourceType: 'pdf',
      filePath: '/path/b.pdf',
      fileHash: 'hash_b',
      createdAt: 2000,
      updatedAt: 2000,
      pageCount: 8,
      tags: [
        TagItem(id: 't4', name: 'E11.9', category: '疾病分類編碼', codeSystem: 'ICD-10-CM', confidence: 0.95),
        TagItem(id: 't5', name: 'SGLT2抑制劑', category: '醫學術語', confidence: 0.92),
        TagItem(id: 't6', name: '慢性腎臟病', category: '疾病/症狀', confidence: 0.88),
      ],
      metadata: {
        'clinical_findings': {
          'icd_codes': [
            {'code': 'E11.9', 'title': '第2型糖尿病', 'system': 'ICD-10-CM'}
          ]
        },
        'knowledge_triplets': [
          {'subject': 'SGLT2抑制劑', 'predicate': '治療改善', 'object': '心血管疾病'}
        ]
      },
    );

    final docC = Document(
      id: 'doc_c',
      title: '文獻C：兒童支氣管氣喘之抗體療法',
      sourceType: 'pdf',
      filePath: '/path/c.pdf',
      fileHash: 'hash_c',
      createdAt: 3000,
      updatedAt: 3000,
      pageCount: 4,
      tags: [
        TagItem(id: 't7', name: '支氣管氣喘', category: '疾病/症狀', confidence: 0.95),
        TagItem(id: 't8', name: 'J45', category: '疾病分類編碼', codeSystem: 'ICD-10-CM', confidence: 0.99),
      ],
    );

    test('findRelatedDocuments 能依共同實體、ICD 編碼與三元組計算出高相關文獻', () {
      final service = KnowledgeGraphService();
      final allDocs = [docA, docB, docC];

      final relatedToA = service.findRelatedDocuments(targetDoc: docA, allDocs: allDocs);

      expect(relatedToA, isNotEmpty);
      // 文獻 B 具有共同 ICD: E11.9, 共同術語: SGLT2抑制劑，以及心血管疾病之連結三元組，應高度相關
      expect(relatedToA.first.document.id, equals('doc_b'));
      expect(relatedToA.first.relevanceScore, greaterThan(0.5));
      expect(relatedToA.first.sharedIcdCodes, contains('E11.9'));
      expect(relatedToA.first.sharedEntities, contains('SGLT2抑制劑'));

      // 文獻 C 無關聯，不應排在第一位，分數遠低或不出現
      expect(relatedToA.any((r) => r.document.id == 'doc_c'), isFalse);
    });

    test('buildGraph 能成功構建包含文獻、疾病、ICD 與概念節點及力導向排版座標之知識圖譜', () {
      final service = KnowledgeGraphService();
      final graph = service.buildGraph(documents: [docA, docB, docC]);

      expect(graph.isNotEmpty, isTrue);
      expect(graph.nodes.any((n) => n.isDocument), isTrue);
      expect(graph.nodes.any((n) => n.isIcd), isTrue);
      expect(graph.edges, isNotEmpty);

      // 檢查節點具備有效座標
      for (final n in graph.nodes) {
        expect(n.x.isFinite, isTrue);
        expect(n.y.isFinite, isTrue);
      }
    });
  });

  group('5. KnowledgeGraphView Widget 視覺化元件測試', () {
    testWidgets('KnowledgeGraphView 正常渲染圖譜畫布與圖例', (tester) async {
      final service = KnowledgeGraphService();
      final doc = Document(
        id: 'doc_1',
        title: '示範文獻',
        sourceType: 'pdf',
        filePath: '/test.pdf',
        fileHash: 'h1',
        createdAt: 100,
        updatedAt: 100,
        tags: [
          TagItem(id: 't1', name: '糖尿病', category: '疾病/症狀'),
          TagItem(id: 't2', name: 'E11', category: '疾病分類編碼', codeSystem: 'ICD-10-CM'),
        ],
      );

      final graph = service.buildGraph(documents: [doc]);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: KnowledgeGraphView(
            graph: graph,
            allDocuments: [doc],
          ),
        ),
      ));

      await tester.pumpAndSettle();

      // 驗證圖例與篩選標籤存在
      expect(find.byType(KnowledgeGraphView), findsOneWidget);
      expect(find.textContaining('全部實體'), findsOneWidget);
      expect(find.text('文獻'), findsWidgets);
      expect(find.text('疾病'), findsOneWidget);
      expect(find.text('ICD'), findsOneWidget);
    });
  });
}
