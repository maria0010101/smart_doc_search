import 'dart:convert';

class Document {
  final String id;
  final String title;
  final String sourceType; // 'pdf' | 'ppt' | 'image'
  final String filePath;
  final String fileHash;
  final int createdAt;
  final int updatedAt;
  final int pageCount;
  final String language;
  final List<TagItem> tags;
  final String summary;
  final List<double>? embedding;
  final Map<String, dynamic> metadata;

  Document({
    required this.id,
    required this.title,
    required this.sourceType,
    required this.filePath,
    required this.fileHash,
    required this.createdAt,
    required this.updatedAt,
    this.pageCount = 1,
    this.language = 'zh-TW',
    this.tags = const [],
    this.summary = '',
    this.embedding,
    this.metadata = const {},
  });

  Document copyWith({
    String? id,
    String? title,
    String? sourceType,
    String? filePath,
    String? fileHash,
    int? createdAt,
    int? updatedAt,
    int? pageCount,
    String? language,
    List<TagItem>? tags,
    String? summary,
    List<double>? embedding,
    Map<String, dynamic>? metadata,
  }) {
    return Document(
      id: id ?? this.id,
      title: title ?? this.title,
      sourceType: sourceType ?? this.sourceType,
      filePath: filePath ?? this.filePath,
      fileHash: fileHash ?? this.fileHash,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      pageCount: pageCount ?? this.pageCount,
      language: language ?? this.language,
      tags: tags ?? this.tags,
      summary: summary ?? this.summary,
      embedding: embedding ?? this.embedding,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'sourceType': sourceType,
      'filePath': filePath,
      'fileHash': fileHash,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'pageCount': pageCount,
      'language': language,
      'tags': tags.map((t) => t.toMap()).toList(),
      'summary': summary,
      'embedding': embedding,
      'metadata': metadata,
    };
  }

  String toJson() => json.encode(toMap());

  factory Document.fromMap(Map<String, dynamic> map) {
    return Document(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      sourceType: map['sourceType'] ?? 'image',
      filePath: map['filePath'] ?? '',
      fileHash: map['fileHash'] ?? '',
      createdAt: (map['createdAt'] is num) ? (map['createdAt'] as num).toInt() : 0,
      updatedAt: (map['updatedAt'] is num) ? (map['updatedAt'] as num).toInt() : 0,
      pageCount: (map['pageCount'] is num) ? (map['pageCount'] as num).toInt() : 1,
      language: map['language'] ?? 'zh-TW',
      tags: (map['tags'] is List)
          ? (map['tags'] as List).map((t) => TagItem.fromMap(Map<String, dynamic>.from(t))).toList()
          : [],
      summary: map['summary'] ?? '',
      embedding: (map['embedding'] is List)
          ? (map['embedding'] as List).map((e) => (e as num).toDouble()).toList()
          : null,
      metadata: (map['metadata'] is Map) ? Map<String, dynamic>.from(map['metadata']) : {},
    );
  }

  factory Document.fromJson(String source) => Document.fromMap(json.decode(source));
}

class TagItem {
  final String id;
  final String name;
  final String category;
  final double confidence;
  final String source; // 'ai_text' | 'ai_image' | 'user' | 'rule'
  final bool verified;

  TagItem({
    required this.id,
    required this.name,
    this.category = '主題',
    this.confidence = 1.0,
    this.source = 'ai_text',
    this.verified = false,
  });

  TagItem copyWith({
    String? id,
    String? name,
    String? category,
    double? confidence,
    String? source,
    bool? verified,
  }) {
    return TagItem(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      confidence: confidence ?? this.confidence,
      source: source ?? this.source,
      verified: verified ?? this.verified,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'confidence': confidence,
      'source': source,
      'verified': verified,
    };
  }

  factory TagItem.fromMap(Map<String, dynamic> map) {
    return TagItem(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      category: map['category'] ?? '主題',
      confidence: (map['confidence'] is num) ? (map['confidence'] as num).toDouble() : 1.0,
      source: map['source'] ?? 'ai_text',
      verified: map['verified'] == true,
    );
  }
}

class PageItem {
  final String id;
  final String documentId;
  final int pageNumber;
  final String imagePath;
  final String ocrText;
  final List<LayoutBlock> layoutBlocks;
  final List<double>? embedding;

  PageItem({
    required this.id,
    required this.documentId,
    required this.pageNumber,
    this.imagePath = '',
    this.ocrText = '',
    this.layoutBlocks = const [],
    this.embedding,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'documentId': documentId,
      'pageNumber': pageNumber,
      'imagePath': imagePath,
      'ocrText': ocrText,
      'layoutBlocks': layoutBlocks.map((b) => b.toMap()).toList(),
      'embedding': embedding,
    };
  }

  String toJson() => json.encode(toMap());

  factory PageItem.fromMap(Map<String, dynamic> map) {
    return PageItem(
      id: map['id'] ?? '',
      documentId: map['documentId'] ?? '',
      pageNumber: (map['pageNumber'] is num) ? (map['pageNumber'] as num).toInt() : 1,
      imagePath: map['imagePath'] ?? '',
      ocrText: map['ocrText'] ?? '',
      layoutBlocks: (map['layoutBlocks'] is List)
          ? (map['layoutBlocks'] as List)
              .map((b) => LayoutBlock.fromMap(Map<String, dynamic>.from(b)))
              .toList()
          : [],
      embedding: (map['embedding'] is List)
          ? (map['embedding'] as List).map((e) => (e as num).toDouble()).toList()
          : null,
    );
  }

  factory PageItem.fromJson(String source) => PageItem.fromMap(json.decode(source));
}

class LayoutBlock {
  final String type; // 'title' | 'paragraph' | 'table' | 'figure' | 'caption' | 'footer'
  final List<double> bbox; // [x1, y1, x2, y2]
  final String text;

  LayoutBlock({
    required this.type,
    this.bbox = const [0, 0, 0, 0],
    required this.text,
  });

  Map<String, dynamic> toMap() {
    return {
      'type': type,
      'bbox': bbox,
      'text': text,
    };
  }

  factory LayoutBlock.fromMap(Map<String, dynamic> map) {
    return LayoutBlock(
      type: map['type'] ?? 'paragraph',
      bbox: (map['bbox'] is List)
          ? (map['bbox'] as List).map((v) => (v as num).toDouble()).toList()
          : const [0, 0, 0, 0],
      text: map['text'] ?? '',
    );
  }
}

class TagDefinition {
  final String id;
  final String name;
  final String category;
  final List<String> aliases;
  final int usageCount;
  final int createdAt;
  final int updatedAt;

  TagDefinition({
    required this.id,
    required this.name,
    this.category = '主題',
    this.aliases = const [],
    this.usageCount = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  TagDefinition copyWith({
    String? id,
    String? name,
    String? category,
    List<String>? aliases,
    int? usageCount,
    int? createdAt,
    int? updatedAt,
  }) {
    return TagDefinition(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      aliases: aliases ?? this.aliases,
      usageCount: usageCount ?? this.usageCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'aliases': aliases,
      'usageCount': usageCount,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  String toJson() => json.encode(toMap());

  factory TagDefinition.fromMap(Map<String, dynamic> map) {
    return TagDefinition(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      category: map['category'] ?? '主題',
      aliases: (map['aliases'] is List) ? (map['aliases'] as List).map((e) => e.toString()).toList() : [],
      usageCount: (map['usageCount'] is num) ? (map['usageCount'] as num).toInt() : 0,
      createdAt: (map['createdAt'] is num) ? (map['createdAt'] as num).toInt() : 0,
      updatedAt: (map['updatedAt'] is num) ? (map['updatedAt'] as num).toInt() : 0,
    );
  }

  factory TagDefinition.fromJson(String source) => TagDefinition.fromMap(json.decode(source));
}

class SearchQuery {
  final List<String> keywords;
  final List<String> tags;
  final String tagMode; // 'AND' | 'OR'
  final String? semanticQuery;
  final DateTime? startDate;
  final DateTime? endDate;
  final List<String> fileTypes;
  final int limit;
  final int offset;

  SearchQuery({
    this.keywords = const [],
    this.tags = const [],
    this.tagMode = 'AND',
    this.semanticQuery,
    this.startDate,
    this.endDate,
    this.fileTypes = const [],
    this.limit = 20,
    this.offset = 0,
  });
}

class SearchResult {
  final List<DocumentHit> items;
  final int total;
  final int tookMs;

  SearchResult({
    required this.items,
    required this.total,
    required this.tookMs,
  });

  factory SearchResult.fromMap(Map<String, dynamic> map) {
    final list = (map['items'] as List?) ?? [];
    return SearchResult(
      items: list.map((e) => DocumentHit.fromMap(Map<String, dynamic>.from(e))).toList(),
      total: (map['total'] is num) ? (map['total'] as num).toInt() : 0,
      tookMs: (map['tookMs'] is num) ? (map['tookMs'] as num).toInt() : 0,
    );
  }
}

class DocumentHit {
  final Document document;
  final double score;
  final String? highlight;
  final List<String> matchedTags;

  DocumentHit({
    required this.document,
    required this.score,
    this.highlight,
    this.matchedTags = const [],
  });

  factory DocumentHit.fromMap(Map<String, dynamic> map) {
    return DocumentHit(
      document: Document.fromMap(Map<String, dynamic>.from(map['document'] ?? {})),
      score: (map['score'] is num) ? (map['score'] as num).toDouble() : 0.0,
      highlight: map['highlight'],
      matchedTags: (map['matchedTags'] is List)
          ? (map['matchedTags'] as List).map((e) => e.toString()).toList()
          : [],
    );
  }
}
