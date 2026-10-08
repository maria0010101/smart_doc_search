import 'dart:math';
import 'package:flutter/material.dart';
import 'package:smart_doc_search/data/models/document_model.dart';
import 'package:smart_doc_search/data/models/knowledge_graph_model.dart';

/// 知識圖譜自訂繪製與互動組件 (CustomPainter Interactive Graph)
class KnowledgeGraphView extends StatefulWidget {
  final KnowledgeGraph graph;
  final List<Document> allDocuments;
  final Function(Document document)? onDocumentTap;
  final Function(String entityName)? onEntityTap;
  final String? initialFocusedNodeId;

  const KnowledgeGraphView({
    super.key,
    required this.graph,
    required this.allDocuments,
    this.onDocumentTap,
    this.onEntityTap,
    this.initialFocusedNodeId,
  });

  @override
  State<KnowledgeGraphView> createState() => _KnowledgeGraphViewState();
}

class _KnowledgeGraphViewState extends State<KnowledgeGraphView> {
  final TransformationController _transformCtrl = TransformationController();
  GraphNode? _selectedNode;
  String _filterType = 'all'; // 'all' | 'document' | 'disease' | 'icd' | 'term' | 'concept'

  bool _initializedTransform = false;
  Size _lastViewportSize = Size.zero;

  @override
  void initState() {
    super.initState();
    if (widget.initialFocusedNodeId != null) {
      _selectedNode = widget.graph.nodes.cast<GraphNode?>().firstWhere(
            (n) => n?.id == widget.initialFocusedNodeId,
            orElse: () => null,
          );
    }
  }

  @override
  void dispose() {
    _transformCtrl.dispose();
    super.dispose();
  }

  void _resetTransform() {
    if (_lastViewportSize.width > 0 && _lastViewportSize.height > 0) {
      final dx = (_lastViewportSize.width - 1000.0) / 2;
      final dy = (_lastViewportSize.height - 900.0) / 2;
      _transformCtrl.value = Matrix4.identity()..setTranslationRaw(dx, dy, 0.0);
    } else {
      _transformCtrl.value = Matrix4.identity();
    }
    setState(() => _selectedNode = null);
  }

  void _handleTapUp(TapUpDetails details, Size canvasSize) {
    final worldX = details.localPosition.dx;
    final worldY = details.localPosition.dy;

    GraphNode? clicked;
    for (final node in widget.graph.nodes) {
      if (_filterType != 'all' && node.type != _filterType && node.type != 'document') continue;
      final dist = sqrt(pow(node.x - worldX, 2) + pow(node.y - worldY, 2));
      if (dist <= node.radius + 14) {
        clicked = node;
        break;
      }
    }

    setState(() => _selectedNode = clicked);

    if (clicked != null) {
      _showNodeActionSheet(clicked);
    }
  }

  void _showNodeActionSheet(GraphNode node) {
    if (node.isDocument) {
      final docId = node.metadata['docId']?.toString();
      final doc = widget.allDocuments.firstWhere((d) => d.id == docId, orElse: () => widget.allDocuments.first);
      showModalBottomSheet(
        context: context,
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.description, color: Colors.indigo, size: 28),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        doc.title,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('標籤數：${doc.tags.length} 個 • 頁數：${doc.pageCount} 頁', style: TextStyle(color: Colors.grey.shade700)),
                if (doc.summary.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    doc.summary,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, height: 1.4),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('開啟文獻詳情'),
                    onPressed: () {
                      Navigator.pop(ctx);
                      widget.onDocumentTap?.call(doc);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      // 實體節點：查詢連結到該實體的所有文獻
      final matchedDocs = widget.allDocuments.where((d) {
        if (d.tags.any((t) => t.name.toLowerCase() == node.label.toLowerCase())) return true;
        final f = d.metadata['clinical_findings'];
        if (f is Map) {
          final p = f['principal_diagnosis']?.toString().toLowerCase();
          if (p == node.label.toLowerCase()) return true;
          final sec = (f['secondary_diagnoses'] as List?)?.map((e) => e.toString().toLowerCase()).toSet() ?? {};
          if (sec.contains(node.label.toLowerCase())) return true;
          final icds = (f['icd_codes'] as List?)?.map((e) => (e['code'] ?? '').toString().toLowerCase()).toSet() ?? {};
          if (icds.contains(node.label.toLowerCase())) return true;
        }
        return false;
      }).toList();

      showModalBottomSheet(
        context: context,
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(_getNodeIcon(node.type), color: _getNodeColor(node.type), size: 28),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            node.label,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '實體類型：${_getNodeTypeLabel(node.type)}',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text('關聯文獻清單 (${matchedDocs.length} 篇)：', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (matchedDocs.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('此實體暫無直接關聯之全文文獻'),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: matchedDocs.length,
                      separatorBuilder: (context, index) => const Divider(height: 1),
                      itemBuilder: (ctx, idx) {
                        final d = matchedDocs[idx];
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.article, size: 20),
                          title: Text(d.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('包含 ${d.tags.length} 個特徵標籤'),
                          trailing: const Icon(Icons.chevron_right, size: 18),
                          onTap: () {
                            Navigator.pop(ctx);
                            widget.onDocumentTap?.call(d);
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.graph.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hub_outlined, size: 48, color: Colors.grey),
            SizedBox(height: 12),
            Text('目前暫無足夠文獻標籤資料以構建知識圖譜', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const canvasWidth = 1000.0;
        const canvasHeight = 900.0;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        _lastViewportSize = Size(constraints.maxWidth, constraints.maxHeight);

        if (!_initializedTransform && constraints.maxWidth > 0 && constraints.maxHeight > 0) {
          _initializedTransform = true;
          final dx = (constraints.maxWidth - canvasWidth) / 2;
          final dy = (constraints.maxHeight - canvasHeight) / 2;
          _transformCtrl.value = Matrix4.identity()..setTranslationRaw(dx, dy, 0.0);
        }

        return Stack(
          children: [
            // Interactive Graph Canvas
            InteractiveViewer(
              transformationController: _transformCtrl,
              boundaryMargin: const EdgeInsets.all(500),
              minScale: 0.2,
              maxScale: 3.5,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) => _handleTapUp(details, Size(canvasWidth, canvasHeight)),
                child: CustomPaint(
                  size: Size(canvasWidth, canvasHeight),
                  painter: _KnowledgeGraphPainter(
                    graph: widget.graph,
                    selectedNode: _selectedNode,
                    filterType: _filterType,
                    isDark: isDark,
                  ),
                ),
              ),
            ),

            // Top Filter Chips
            Positioned(
              top: 12,
              left: 12,
              right: 60,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildFilterChip('all', '全部實體 (${widget.graph.nodes.length})'),
                    const SizedBox(width: 6),
                    _buildFilterChip('document', '文獻'),
                    const SizedBox(width: 6),
                    _buildFilterChip('disease', '疾病/診斷'),
                    const SizedBox(width: 6),
                    _buildFilterChip('icd', 'ICD 編碼'),
                    const SizedBox(width: 6),
                    _buildFilterChip('term', '醫學術語'),
                    const SizedBox(width: 6),
                    _buildFilterChip('concept', '知識三元組'),
                  ],
                ),
              ),
            ),

            // Control Buttons
            Positioned(
              right: 12,
              top: 12,
              child: FloatingActionButton.small(
                heroTag: 'reset_graph_view',
                tooltip: '重設視角',
                onPressed: _resetTransform,
                child: const Icon(Icons.center_focus_strong),
              ),
            ),

            // Bottom Legend
            Positioned(
              left: 12,
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: (isDark ? Colors.grey.shade900 : Colors.white).withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildLegendItem(Colors.indigo, '文獻'),
                    const SizedBox(width: 10),
                    _buildLegendItem(Colors.red.shade400, '疾病'),
                    const SizedBox(width: 10),
                    _buildLegendItem(Colors.teal, 'ICD'),
                    const SizedBox(width: 10),
                    _buildLegendItem(Colors.purple, '術語'),
                    const SizedBox(width: 10),
                    _buildLegendItem(Colors.amber.shade800, '關係'),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFilterChip(String type, String label) {
    final isSelected = _filterType == type;
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: isSelected,
      onSelected: (_) => setState(() => _filterType = type),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }

  Color _getNodeColor(String type) {
    switch (type) {
      case 'document': return Colors.indigo;
      case 'disease': return Colors.red.shade400;
      case 'icd': return Colors.teal;
      case 'term': return Colors.purple;
      case 'concept': return Colors.amber.shade800;
      default: return Colors.blueGrey;
    }
  }

  IconData _getNodeIcon(String type) {
    switch (type) {
      case 'document': return Icons.description;
      case 'disease': return Icons.coronavirus_outlined;
      case 'icd': return Icons.local_offer;
      case 'term': return Icons.medical_services_outlined;
      case 'concept': return Icons.bubble_chart;
      default: return Icons.circle;
    }
  }

  String _getNodeTypeLabel(String type) {
    switch (type) {
      case 'document': return '文獻';
      case 'disease': return '疾病/主要診斷';
      case 'icd': return 'ICD-10 分類編碼';
      case 'term': return '醫學專有術語';
      case 'concept': return '知識三元組概念';
      default: return '知識實體';
    }
  }
}

class Vector3 {
  final double x;
  final double y;
  final double z;
  Vector3(this.x, this.y, this.z);
}

extension Matrix4Ext on Matrix4 {
  Vector3 applyToVector3(Vector3 arg) {
    final x = storage[0] * arg.x + storage[4] * arg.y + storage[8] * arg.z + storage[12];
    final y = storage[1] * arg.x + storage[5] * arg.y + storage[9] * arg.z + storage[13];
    final z = storage[2] * arg.x + storage[6] * arg.y + storage[10] * arg.z + storage[14];
    return Vector3(x, y, z);
  }
}

class _KnowledgeGraphPainter extends CustomPainter {
  final KnowledgeGraph graph;
  final GraphNode? selectedNode;
  final String filterType;
  final bool isDark;

  _KnowledgeGraphPainter({
    required this.graph,
    required this.selectedNode,
    required this.filterType,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final nodeMap = {for (var n in graph.nodes) n.id: n};

    // 取得選中節點的關聯鄰居 ID 集合
    final neighborIds = <String>{};
    if (selectedNode != null) {
      neighborIds.add(selectedNode!.id);
      for (final e in graph.edges) {
        if (e.sourceId == selectedNode!.id) neighborIds.add(e.targetId);
        if (e.targetId == selectedNode!.id) neighborIds.add(e.sourceId);
      }
    }

    // 1. 繪製邊 (Edges)
    for (final edge in graph.edges) {
      final src = nodeMap[edge.sourceId];
      final tgt = nodeMap[edge.targetId];
      if (src == null || tgt == null) continue;

      if (filterType != 'all') {
        if (src.type != filterType && src.type != 'document' && tgt.type != filterType && tgt.type != 'document') {
          continue;
        }
      }

      final isEdgeHighlighted = selectedNode != null &&
          (edge.sourceId == selectedNode!.id || edge.targetId == selectedNode!.id);

      final linePaint = Paint()
        ..color = isEdgeHighlighted
            ? Colors.amber.shade700
            : (isDark ? Colors.white24 : Colors.black12)
        ..strokeWidth = isEdgeHighlighted ? 2.5 : 1.2
        ..style = PaintingStyle.stroke;

      canvas.drawLine(Offset(src.x, src.y), Offset(tgt.x, tgt.y), linePaint);

      // 若高亮則顯示關係名稱
      if (isEdgeHighlighted && edge.label.isNotEmpty) {
        final midX = (src.x + tgt.x) / 2;
        final midY = (src.y + tgt.y) / 2;
        final textSpan = TextSpan(
          text: edge.label,
          style: TextStyle(
            color: isDark ? Colors.amberAccent : Colors.amber.shade900,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            backgroundColor: (isDark ? Colors.black87 : Colors.white70),
          ),
        );
        final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr);
        tp.layout();
        tp.paint(canvas, Offset(midX - tp.width / 2, midY - tp.height / 2));
      }
    }

    // 2. 繪製節點 (Nodes)
    for (final node in graph.nodes) {
      if (filterType != 'all' && node.type != filterType && node.type != 'document') {
        continue;
      }

      final isSelected = selectedNode?.id == node.id;
      final isNeighbor = neighborIds.contains(node.id);
      final hasSelection = selectedNode != null;

      final nodePaint = Paint()
        ..color = _getNodeColor(node.type).withValues(alpha: hasSelection && !isNeighbor ? 0.3 : 1.0)
        ..style = PaintingStyle.fill;

      // 繪製陰影/發光外圈
      if (isSelected) {
        final glowPaint = Paint()
          ..color = Colors.amber.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6.0;
        canvas.drawCircle(Offset(node.x, node.y), node.radius + 4, glowPaint);
      }

      canvas.drawCircle(Offset(node.x, node.y), node.radius, nodePaint);

      // 節點邊框
      final borderPaint = Paint()
        ..color = isSelected
            ? Colors.amber
            : (isDark ? Colors.white70 : Colors.white)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelected ? 2.5 : 1.5;
      canvas.drawCircle(Offset(node.x, node.y), node.radius, borderPaint);

      // 節點文字
      final textSpan = TextSpan(
        text: node.label,
        style: TextStyle(
          color: isDark ? Colors.white : Colors.black87,
          fontSize: node.isDocument ? 11 : 10,
          fontWeight: isSelected || node.isDocument ? FontWeight.bold : FontWeight.normal,
        ),
      );
      final tp = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '...',
      );
      tp.layout(maxWidth: 80);
      tp.paint(canvas, Offset(node.x - tp.width / 2, node.y + node.radius + 3));
    }
  }

  Color _getNodeColor(String type) {
    switch (type) {
      case 'document': return Colors.indigo;
      case 'disease': return Colors.red.shade400;
      case 'icd': return Colors.teal;
      case 'term': return Colors.purple;
      case 'concept': return Colors.amber.shade800;
      default: return Colors.blueGrey;
    }
  }

  @override
  bool shouldRepaint(covariant _KnowledgeGraphPainter oldDelegate) {
    return oldDelegate.graph != graph ||
        oldDelegate.selectedNode != selectedNode ||
        oldDelegate.filterType != filterType ||
        oldDelegate.isDark != isDark;
  }
}
