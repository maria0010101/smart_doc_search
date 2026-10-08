import 'dart:math';
import 'package:smart_doc_search/data/models/document_model.dart';
import 'package:smart_doc_search/data/models/knowledge_graph_model.dart';

/// 知識圖譜服務 (參考 jiangnanboy/llm-knowledge-graph 架構)
/// 負責：
/// 1. 將全庫文獻抽取之實體、標籤、ICD編碼與三元組整合建構為多維知識圖譜
/// 2. 檢索/查詢時計算並提供跨文獻關聯資訊 (Cross-Document Related Information)
/// 3. 力導向佈局演算法 (Force-directed layout)，計算節點畫布座標
class KnowledgeGraphService {
  /// 建構知識圖譜（支援全局或特定文獻為核心之子圖譜）
  KnowledgeGraph buildGraph({
    required List<Document> documents,
    String? focusDocId,
    int maxNodes = 65,
    double canvasWidth = 1000,
    double canvasHeight = 900,
  }) {
    if (documents.isEmpty) {
      return KnowledgeGraph(nodes: [], edges: []);
    }

    final nodesMap = <String, GraphNode>{};
    final edgesList = <GraphEdge>[];
    final edgeKeys = <String>{};

    void addEdge(String src, String tgt, String label, double weight) {
      if (src == tgt) return;
      final key = '$src--$tgt--$label';
      final revKey = '$tgt--$src--$label';
      if (!edgeKeys.contains(key) && !edgeKeys.contains(revKey)) {
        edgeKeys.add(key);
        edgesList.add(GraphEdge(
          id: 'edge_${edgesList.length}',
          sourceId: src,
          targetId: tgt,
          label: label,
          weight: weight,
        ));
      }
    }

    // 1. 若有聚焦文獻，優先以聚焦文獻及其關聯文獻建構
    final targetDocs = focusDocId != null
        ? _filterFocusedDocs(documents, focusDocId)
        : documents;

    // 2. 加入文獻節點
    for (final doc in targetDocs) {
      final docNodeId = 'doc_${doc.id}';
      if (!nodesMap.containsKey(docNodeId)) {
        nodesMap[docNodeId] = GraphNode(
          id: docNodeId,
          label: doc.title.length > 18 ? '${doc.title.substring(0, 16)}...' : doc.title,
          type: 'document',
          radius: 28.0,
          metadata: {
            'docId': doc.id,
            'title': doc.title,
            'tagsCount': doc.tags.length,
          },
        );
      }
    }

    // 3. 加入各文獻的標籤實體節點與連線
    for (final doc in targetDocs) {
      final docNodeId = 'doc_${doc.id}';

      // a) 標籤節點
      for (final tag in doc.tags) {
        if (nodesMap.length >= maxNodes) break;
        final normName = tag.name.trim();
        if (normName.isEmpty) continue;

        String nodeType = 'term';
        double radius = 18.0;
        if (tag.category == '疾病分類編碼' || tag.codeSystem != null) {
          nodeType = 'icd';
          radius = 20.0;
        } else if (tag.category == '疾病/症狀') {
          nodeType = 'disease';
          radius = 20.0;
        }

        final entityNodeId = 'entity_${normName.toLowerCase()}';
        if (!nodesMap.containsKey(entityNodeId)) {
          nodesMap[entityNodeId] = GraphNode(
            id: entityNodeId,
            label: normName,
            type: nodeType,
            radius: radius,
            metadata: {
              'category': tag.category,
              'codeSystem': tag.codeSystem,
              'pageNumber': tag.pageNumber,
            },
          );
        }

        addEdge(docNodeId, entityNodeId, tag.codeSystem ?? '標籤', 1.0);
      }

      // b) RapidDoc 臨床數據節點 (ICD 與主要診斷)
      final rawFinding = doc.metadata['clinical_findings'];
      if (rawFinding != null) {
        try {
          final finding = ClinicalFinding.fromMap(Map<String, dynamic>.from(rawFinding));
          for (final icd in finding.icdCodes) {
            if (nodesMap.length >= maxNodes) break;
            final icdId = 'icd_${icd.code.toLowerCase()}';
            if (!nodesMap.containsKey(icdId)) {
              nodesMap[icdId] = GraphNode(
                id: icdId,
                label: '${icd.code} ${icd.title}',
                type: 'icd',
                radius: 22.0,
                metadata: {'code': icd.code, 'title': icd.title, 'system': icd.system},
              );
            }
            addEdge(docNodeId, icdId, '編碼', 1.5);
          }

          if (finding.principalDiagnosis != null && finding.principalDiagnosis!.isNotEmpty) {
            final diagId = 'disease_${finding.principalDiagnosis!.toLowerCase()}';
            if (!nodesMap.containsKey(diagId)) {
              nodesMap[diagId] = GraphNode(
                id: diagId,
                label: finding.principalDiagnosis!,
                type: 'disease',
                radius: 22.0,
              );
            }
            addEdge(docNodeId, diagId, '主要診斷', 2.0);
          }
        } catch (_) {}
      }

      // c) 三元組節點與關係連線 (llm-knowledge-graph)
      final rawTriplets = doc.metadata['knowledge_triplets'];
      if (rawTriplets is List) {
        for (final item in rawTriplets) {
          if (nodesMap.length >= maxNodes) break;
          try {
            final t = KnowledgeTriplet.fromMap(Map<String, dynamic>.from(item));
            if (t.subject.isEmpty || t.object.isEmpty) continue;

            final subId = 'term_${t.subject.toLowerCase()}';
            final objId = 'term_${t.object.toLowerCase()}';

            if (!nodesMap.containsKey(subId)) {
              nodesMap[subId] = GraphNode(id: subId, label: t.subject, type: 'concept', radius: 18.0);
            }
            if (!nodesMap.containsKey(objId)) {
              nodesMap[objId] = GraphNode(id: objId, label: t.object, type: 'concept', radius: 18.0);
            }

            addEdge(subId, objId, t.predicate.isNotEmpty ? t.predicate : '關聯', 1.5);
            addEdge(docNodeId, subId, '提及', 0.8);
          } catch (_) {}
        }
      }
    }

    final nodesList = nodesMap.values.toList();

    // 4. 力導向模擬計算 (Force-directed layout calculation)
    _applyForceDirectedLayout(
      nodes: nodesList,
      edges: edgesList,
      width: canvasWidth,
      height: canvasHeight,
      iterations: 60,
    );

    return KnowledgeGraph(
      nodes: nodesList,
      edges: edgesList,
    );
  }

  /// 計算特定文獻與所有其他文獻的跨文獻關聯資訊 (Cross-Document Related Information)
  List<RelatedDocumentInfo> findRelatedDocuments({
    required Document targetDoc,
    required List<Document> allDocs,
    int limit = 5,
  }) {
    final results = <RelatedDocumentInfo>[];

    // 目標文獻特徵集
    final targetTagMap = <String, TagItem>{};
    final targetIcdCodes = <String>{};
    for (final t in targetDoc.tags) {
      final k = t.name.trim().toLowerCase();
      if (k.isNotEmpty) targetTagMap[k] = t;
      if (t.category == '疾病分類編碼' || t.codeSystem != null) {
        targetIcdCodes.add(t.name.trim().toUpperCase());
      }
    }

    // 目標文獻 RapidDoc ICD
    final targetFindingRaw = targetDoc.metadata['clinical_findings'];
    if (targetFindingRaw != null) {
      try {
        final f = ClinicalFinding.fromMap(Map<String, dynamic>.from(targetFindingRaw));
        for (final icd in f.icdCodes) {
          targetIcdCodes.add(icd.code.toUpperCase());
        }
      } catch (_) {}
    }

    // 目標文獻三元組
    final targetTriplets = <KnowledgeTriplet>[];
    final targetRawTriplets = targetDoc.metadata['knowledge_triplets'];
    if (targetRawTriplets is List) {
      for (final r in targetRawTriplets) {
        try {
          targetTriplets.add(KnowledgeTriplet.fromMap(Map<String, dynamic>.from(r)));
        } catch (_) {}
      }
    }

    for (final other in allDocs) {
      if (other.id == targetDoc.id) continue;

      double score = 0.0;
      final sharedEntities = <String>[];
      final sharedIcds = <String>[];
      final connectingTriplets = <KnowledgeTriplet>[];

      // 1. 共同標籤與實體加權
      for (final t in other.tags) {
        final k = t.name.trim().toLowerCase();
        if (targetTagMap.containsKey(k)) {
          final targetTag = targetTagMap[k]!;
          sharedEntities.add(t.name);
          double weight = (t.category == '疾病/症狀') ? 2.5 : 1.0;
          score += (targetTag.confidence * t.confidence * weight);
        }
      }

      // 2. 共同 ICD-10 代碼高度加權 (+3.5 分)
      final otherIcdCodes = <String>{};
      for (final t in other.tags) {
        if (t.category == '疾病分類編碼' || t.codeSystem != null) {
          otherIcdCodes.add(t.name.trim().toUpperCase());
        }
      }
      final otherFindingRaw = other.metadata['clinical_findings'];
      if (otherFindingRaw != null) {
        try {
          final f = ClinicalFinding.fromMap(Map<String, dynamic>.from(otherFindingRaw));
          for (final icd in f.icdCodes) {
            otherIcdCodes.add(icd.code.toUpperCase());
          }
        } catch (_) {}
      }

      for (final icd in otherIcdCodes) {
        if (targetIcdCodes.contains(icd)) {
          sharedIcds.add(icd);
          score += 3.5;
        }
      }

      // 3. 三元組鏈接關聯
      final otherRawTriplets = other.metadata['knowledge_triplets'];
      if (otherRawTriplets is List) {
        for (final r in otherRawTriplets) {
          try {
            final t = KnowledgeTriplet.fromMap(Map<String, dynamic>.from(r));
            for (final tt in targetTriplets) {
              if (tt.subject.toLowerCase() == t.subject.toLowerCase() ||
                  tt.object.toLowerCase() == t.object.toLowerCase() ||
                  tt.object.toLowerCase() == t.subject.toLowerCase()) {
                connectingTriplets.add(t);
                score += 2.0;
                break;
              }
            }
          } catch (_) {}
        }
      }

      if (score > 0.0) {
        // 標準化分數至 0.0 ~ 1.0 (以 10.0 為飽和值)
        final normalizedScore = (score / 10.0).clamp(0.05, 1.0);
        results.add(RelatedDocumentInfo(
          document: other,
          relevanceScore: normalizedScore,
          sharedEntities: sharedEntities.toSet().toList(),
          sharedIcdCodes: sharedIcds.toSet().toList(),
          connectingTriplets: connectingTriplets.take(4).toList(),
        ));
      }
    }

    results.sort((a, b) => b.relevanceScore.compareTo(a.relevanceScore));
    return results.take(limit).toList();
  }

  /// 依特定實體名稱檢索所有包含該實體之文獻
  List<Document> findDocumentsByEntity({
    required String entityName,
    required List<Document> allDocs,
  }) {
    final norm = entityName.trim().toLowerCase();
    if (norm.isEmpty) return [];

    final matched = <Document>[];
    for (final doc in allDocs) {
      bool found = false;
      for (final t in doc.tags) {
        if (t.name.trim().toLowerCase() == norm) {
          found = true;
          break;
        }
      }
      if (!found) {
        final fRaw = doc.metadata['clinical_findings'];
        if (fRaw != null) {
          try {
            final f = ClinicalFinding.fromMap(Map<String, dynamic>.from(fRaw));
            if (f.principalDiagnosis?.toLowerCase() == norm ||
                f.secondaryDiagnoses.any((s) => s.toLowerCase() == norm) ||
                f.icdCodes.any((c) => c.code.toLowerCase() == norm || c.title.toLowerCase().contains(norm))) {
              found = true;
            }
          } catch (_) {}
        }
      }
      if (found) {
        matched.add(doc);
      }
    }
    return matched;
  }

  List<Document> _filterFocusedDocs(List<Document> allDocs, String focusDocId) {
    final focusDoc = allDocs.firstWhere((d) => d.id == focusDocId, orElse: () => allDocs.first);
    final related = findRelatedDocuments(targetDoc: focusDoc, allDocs: allDocs, limit: 6);
    final relatedIds = related.map((r) => r.document.id).toSet();
    relatedIds.add(focusDoc.id);
    return allDocs.where((d) => relatedIds.contains(d.id)).toList();
  }

  /// 力導向排版演算法 (Force-directed / Spring-embedder algorithm)
  void _applyForceDirectedLayout({
    required List<GraphNode> nodes,
    required List<GraphEdge> edges,
    required double width,
    required double height,
    int iterations = 60,
  }) {
    if (nodes.isEmpty) return;

    final rand = Random(42);
    final centerX = width / 2;
    final centerY = height / 2;
    final radius = min(width, height) * 0.38;

    // 初始位置：環形分散分佈
    for (int i = 0; i < nodes.length; i++) {
      final angle = (2 * pi * i) / nodes.length;
      final dist = radius * (0.6 + 0.4 * (i % 2));
      nodes[i].x = centerX + dist * cos(angle) + (rand.nextDouble() - 0.5) * 40;
      nodes[i].y = centerY + dist * sin(angle) + (rand.nextDouble() - 0.5) * 40;
    }

    final nodeIndexMap = <String, GraphNode>{};
    for (final n in nodes) {
      nodeIndexMap[n.id] = n;
    }

    // 迭代模擬力
    const kRepulsion = 4500.0;
    const kAttraction = 0.035;
    const damping = 0.85;

    for (int iter = 0; iter < iterations; iter++) {
      // 1. 節點間斥力
      for (int i = 0; i < nodes.length; i++) {
        for (int j = i + 1; j < nodes.length; j++) {
          final n1 = nodes[i];
          final n2 = nodes[j];
          final dx = n2.x - n1.x;
          final dy = n2.y - n1.y;
          final distSq = dx * dx + dy * dy + 100.0;
          final dist = sqrt(distSq);

          final force = kRepulsion / distSq;
          final fx = (dx / dist) * force;
          final fy = (dy / dist) * force;

          n1.vx -= fx;
          n1.vy -= fy;
          n2.vx += fx;
          n2.vy += fy;
        }
      }

      // 2. 邊引力
      for (final e in edges) {
        final src = nodeIndexMap[e.sourceId];
        final tgt = nodeIndexMap[e.targetId];
        if (src == null || tgt == null) continue;

        final dx = tgt.x - src.x;
        final dy = tgt.y - src.y;
        final dist = sqrt(dx * dx + dy * dy);

        final force = dist * kAttraction * e.weight;
        final fx = (dx / (dist + 0.001)) * force;
        final fy = (dy / (dist + 0.001)) * force;

        src.vx += fx;
        src.vy += fy;
        tgt.vx -= fx;
        tgt.vy -= fy;
      }

      // 3. 向心力與阻尼位移更新
      for (final n in nodes) {
        // 微弱向心重力
        n.vx += (centerX - n.x) * 0.01;
        n.vy += (centerY - n.y) * 0.01;

        n.vx *= damping;
        n.vy *= damping;

        n.x += n.vx.clamp(-30.0, 30.0);
        n.y += n.vy.clamp(-30.0, 30.0);

        // 保持在畫布邊界內
        n.x = n.x.clamp(40.0, width - 40.0);
        n.y = n.y.clamp(40.0, height - 40.0);
      }
    }
  }
}
