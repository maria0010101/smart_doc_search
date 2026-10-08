import 'dart:convert';
import 'package:smart_doc_search/data/models/document_model.dart';

/// 學術元數據模型 (參考 GraphifyPDF)
/// 涵蓋作者、DOI、出版年份、期刊來源、引用與關鍵字
class AcademicMetadata {
  final List<String> authors;
  final String? doi;
  final int? publicationYear;
  final String? journal;
  final List<String> citations;
  final List<String> keywords;

  AcademicMetadata({
    this.authors = const [],
    this.doi,
    this.publicationYear,
    this.journal,
    this.citations = const [],
    this.keywords = const [],
  });

  bool get isEmpty =>
      authors.isEmpty &&
      (doi == null || doi!.isEmpty) &&
      publicationYear == null &&
      (journal == null || journal!.isEmpty) &&
      citations.isEmpty &&
      keywords.isEmpty;

  bool get isNotEmpty => !isEmpty;

  AcademicMetadata copyWith({
    List<String>? authors,
    String? doi,
    int? publicationYear,
    String? journal,
    List<String>? citations,
    List<String>? keywords,
  }) {
    return AcademicMetadata(
      authors: authors ?? this.authors,
      doi: doi ?? this.doi,
      publicationYear: publicationYear ?? this.publicationYear,
      journal: journal ?? this.journal,
      citations: citations ?? this.citations,
      keywords: keywords ?? this.keywords,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'authors': authors,
      'doi': doi,
      'publication_year': publicationYear,
      'journal': journal,
      'citations': citations,
      'keywords': keywords,
    };
  }

  String toJson() => json.encode(toMap());

  factory AcademicMetadata.fromMap(Map<String, dynamic> map) {
    int? year;
    final rawYear = map['publication_year'] ?? map['publicationYear'] ?? map['year'];
    if (rawYear != null) {
      year = int.tryParse(rawYear.toString());
    }

    return AcademicMetadata(
      authors: (map['authors'] as List?)?.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList() ?? const [],
      doi: map['doi']?.toString().trim(),
      publicationYear: year,
      journal: map['journal']?.toString().trim() ?? map['venue']?.toString().trim(),
      citations: (map['citations'] as List?)?.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList() ?? const [],
      keywords: (map['keywords'] as List?)?.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList() ?? const [],
    );
  }

  factory AcademicMetadata.fromJson(dynamic source) {
    if (source is Map<String, dynamic>) {
      return AcademicMetadata.fromMap(source);
    }
    return AcademicMetadata.fromMap(json.decode(source.toString()));
  }
}

/// 臨床檢驗指標與數值 (參考 RapidDoc 結構化數據擷取)
class LabValueItem {
  final String testName;
  final String value;
  final String? unit;
  final String? referenceRange;
  final int? pageNumber;

  LabValueItem({
    required this.testName,
    required this.value,
    this.unit,
    this.referenceRange,
    this.pageNumber,
  });

  Map<String, dynamic> toMap() {
    return {
      'test_name': testName,
      'value': value,
      'unit': unit,
      'reference_range': referenceRange,
      'page_number': pageNumber,
    };
  }

  factory LabValueItem.fromMap(Map<String, dynamic> map) {
    return LabValueItem(
      testName: (map['test_name'] ?? map['testName'] ?? map['name'] ?? '').toString().trim(),
      value: (map['value'] ?? '').toString().trim(),
      unit: map['unit']?.toString().trim(),
      referenceRange: (map['reference_range'] ?? map['referenceRange'])?.toString().trim(),
      pageNumber: (map['page_number'] ?? map['pageNumber']) != null
          ? int.tryParse((map['page_number'] ?? map['pageNumber']).toString())
          : null,
    );
  }
}

/// 疾病分類與編碼項目 (ICD-10-CM / ICD-10-PCS)
class IcdCodeItem {
  final String code;
  final String title;
  final String system; // 'ICD-10-CM' | 'ICD-10-PCS' | 'SNOMED-CT'
  final int? pageNumber;

  IcdCodeItem({
    required this.code,
    required this.title,
    this.system = 'ICD-10-CM',
    this.pageNumber,
  });

  Map<String, dynamic> toMap() {
    return {
      'code': code,
      'title': title,
      'system': system,
      'page_number': pageNumber,
    };
  }

  factory IcdCodeItem.fromMap(Map<String, dynamic> map) {
    return IcdCodeItem(
      code: (map['code'] ?? '').toString().trim().toUpperCase(),
      title: (map['title'] ?? map['name'] ?? '').toString().trim(),
      system: (map['system'] ?? map['code_system'] ?? 'ICD-10-CM').toString().trim(),
      pageNumber: (map['page_number'] ?? map['pageNumber']) != null
          ? int.tryParse((map['page_number'] ?? map['pageNumber']).toString())
          : null,
    );
  }
}

/// 臨床與疾病分類結構化擷取結果 (參考 RapidDoc)
class ClinicalFinding {
  final String? principalDiagnosis;
  final List<String> secondaryDiagnoses;
  final List<String> procedures;
  final List<LabValueItem> labValues;
  final List<IcdCodeItem> icdCodes;

  ClinicalFinding({
    this.principalDiagnosis,
    this.secondaryDiagnoses = const [],
    this.procedures = const [],
    this.labValues = const [],
    this.icdCodes = const [],
  });

  bool get isEmpty =>
      (principalDiagnosis == null || principalDiagnosis!.isEmpty) &&
      secondaryDiagnoses.isEmpty &&
      procedures.isEmpty &&
      labValues.isEmpty &&
      icdCodes.isEmpty;

  bool get isNotEmpty => !isEmpty;

  ClinicalFinding copyWith({
    String? principalDiagnosis,
    List<String>? secondaryDiagnoses,
    List<String>? procedures,
    List<LabValueItem>? labValues,
    List<IcdCodeItem>? icdCodes,
  }) {
    return ClinicalFinding(
      principalDiagnosis: principalDiagnosis ?? this.principalDiagnosis,
      secondaryDiagnoses: secondaryDiagnoses ?? this.secondaryDiagnoses,
      procedures: procedures ?? this.procedures,
      labValues: labValues ?? this.labValues,
      icdCodes: icdCodes ?? this.icdCodes,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'principal_diagnosis': principalDiagnosis,
      'secondary_diagnoses': secondaryDiagnoses,
      'procedures': procedures,
      'lab_values': labValues.map((v) => v.toMap()).toList(),
      'icd_codes': icdCodes.map((c) => c.toMap()).toList(),
    };
  }

  String toJson() => json.encode(toMap());

  factory ClinicalFinding.fromMap(Map<String, dynamic> map) {
    return ClinicalFinding(
      principalDiagnosis: (map['principal_diagnosis'] ?? map['principalDiagnosis'])?.toString().trim(),
      secondaryDiagnoses: (map['secondary_diagnoses'] as List? ?? map['secondaryDiagnoses'] as List?)
              ?.map((e) => e.toString().trim())
              .where((s) => s.isNotEmpty)
              .toList() ??
          const [],
      procedures: (map['procedures'] as List?)
              ?.map((e) => e.toString().trim())
              .where((s) => s.isNotEmpty)
              .toList() ??
          const [],
      labValues: (map['lab_values'] as List? ?? map['labValues'] as List?)
              ?.map((e) => LabValueItem.fromMap(Map<String, dynamic>.from(e)))
              .toList() ??
          const [],
      icdCodes: (map['icd_codes'] as List? ?? map['icdCodes'] as List?)
              ?.map((e) => IcdCodeItem.fromMap(Map<String, dynamic>.from(e)))
              .toList() ??
          const [],
    );
  }

  factory ClinicalFinding.fromJson(dynamic source) {
    if (source is Map<String, dynamic>) {
      return ClinicalFinding.fromMap(source);
    }
    return ClinicalFinding.fromMap(json.decode(source.toString()));
  }
}

/// 知識三元組 (Subject-Predicate-Object，參考 llm-knowledge-graph)
class KnowledgeTriplet {
  final String subject;
  final String predicate;
  final String object;
  final double confidence;
  final int? pageNumber;

  KnowledgeTriplet({
    required this.subject,
    required this.predicate,
    required this.object,
    this.confidence = 0.9,
    this.pageNumber,
  });

  Map<String, dynamic> toMap() {
    return {
      'subject': subject,
      'predicate': predicate,
      'object': object,
      'confidence': confidence,
      'page_number': pageNumber,
    };
  }

  String toJson() => json.encode(toMap());

  factory KnowledgeTriplet.fromMap(Map<String, dynamic> map) {
    return KnowledgeTriplet(
      subject: (map['subject'] ?? map['source'] ?? map['head'] ?? '').toString().trim(),
      predicate: (map['predicate'] ?? map['relation'] ?? '').toString().trim(),
      object: (map['object'] ?? map['target'] ?? map['tail'] ?? '').toString().trim(),
      confidence: (map['confidence'] is num) ? (map['confidence'] as num).toDouble() : 0.9,
      pageNumber: (map['page_number'] ?? map['pageNumber']) != null
          ? int.tryParse((map['page_number'] ?? map['pageNumber']).toString())
          : null,
    );
  }

  factory KnowledgeTriplet.fromJson(dynamic source) {
    if (source is Map<String, dynamic>) {
      return KnowledgeTriplet.fromMap(source);
    }
    return KnowledgeTriplet.fromMap(json.decode(source.toString()));
  }

  @override
  String toString() => '$subject -[$predicate]-> $object';
}

/// 跨文獻相關聯資訊 (Cross-Document Related Information)
class RelatedDocumentInfo {
  final Document document;
  final double relevanceScore; // 0.0 to 1.0
  final List<String> sharedEntities; // 共同實體 (疾病、術語、概念)
  final List<String> sharedIcdCodes; // 共同 ICD 代碼
  final List<KnowledgeTriplet> connectingTriplets; // 連結兩篇文獻的知識三元組

  RelatedDocumentInfo({
    required this.document,
    required this.relevanceScore,
    this.sharedEntities = const [],
    this.sharedIcdCodes = const [],
    this.connectingTriplets = const [],
  });

  int get scorePercent => (relevanceScore * 100).clamp(0, 100).round();
}

/// 知識圖譜節點
class GraphNode {
  final String id;
  final String label;
  final String type; // 'document' | 'disease' | 'procedure' | 'icd' | 'term' | 'concept' | 'author'
  final Map<String, dynamic> metadata;
  double x;
  double y;
  double vx;
  double vy;
  final double radius;

  GraphNode({
    required this.id,
    required this.label,
    required this.type,
    this.metadata = const {},
    this.x = 0.0,
    this.y = 0.0,
    this.vx = 0.0,
    this.vy = 0.0,
    this.radius = 24.0,
  });

  bool get isDocument => type == 'document';
  bool get isIcd => type == 'icd';
  bool get isDisease => type == 'disease';
}

/// 知識圖譜連線
class GraphEdge {
  final String id;
  final String sourceId;
  final String targetId;
  final String label; // 關係說明 (e.g. '提及', '治療', '併發症', '作者', '編碼')
  final double weight;

  GraphEdge({
    required this.id,
    required this.sourceId,
    required this.targetId,
    this.label = '',
    this.weight = 1.0,
  });
}

/// 完整知識圖譜資料結構
class KnowledgeGraph {
  final List<GraphNode> nodes;
  final List<GraphEdge> edges;

  KnowledgeGraph({
    required this.nodes,
    required this.edges,
  });

  bool get isEmpty => nodes.isEmpty;
  bool get isNotEmpty => nodes.isNotEmpty;
}
