import 'package:flutter/material.dart';
import 'package:smart_doc_search/core/services/knowledge_graph_service.dart';
import 'package:smart_doc_search/data/datasources/ollama_client.dart';
import 'package:smart_doc_search/data/models/document_model.dart';
import 'package:smart_doc_search/data/models/knowledge_graph_model.dart';
import 'package:smart_doc_search/data/repositories/document_repository.dart';
import 'package:smart_doc_search/features/document/document_detail_screen.dart';
import 'package:smart_doc_search/features/graph/widgets/knowledge_graph_view.dart';

/// 完整知識圖譜視覺化畫面
class KnowledgeGraphScreen extends StatefulWidget {
  final DocumentRepository repository;
  final OllamaClient ollamaClient;
  final String? focusDocId;
  final String? focusDocTitle;

  const KnowledgeGraphScreen({
    super.key,
    required this.repository,
    required this.ollamaClient,
    this.focusDocId,
    this.focusDocTitle,
  });

  @override
  State<KnowledgeGraphScreen> createState() => _KnowledgeGraphScreenState();
}

class _KnowledgeGraphScreenState extends State<KnowledgeGraphScreen> {
  final KnowledgeGraphService _graphService = KnowledgeGraphService();
  List<Document> _documents = [];
  KnowledgeGraph? _graph;
  bool _isLoading = true;
  String? _focusedDocId;

  @override
  void initState() {
    super.initState();
    _focusedDocId = widget.focusDocId;
    _loadGraphData();
  }

  Future<void> _loadGraphData() async {
    setState(() => _isLoading = true);
    final docs = await widget.repository.getAllDocuments();
    final graph = _graphService.buildGraph(
      documents: docs,
      focusDocId: _focusedDocId,
      maxNodes: 75,
    );

    if (mounted) {
      setState(() {
        _documents = docs;
        _graph = graph;
        _isLoading = false;
      });
    }
  }

  void _navigateToDoc(Document doc) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DocumentDetailScreen(
          documentId: doc.id,
          repository: widget.repository,
          ollamaClient: widget.ollamaClient,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.focusDocTitle != null
        ? '知識圖譜：${widget.focusDocTitle}'
        : '文獻資料庫知識圖譜';

    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        actions: [
          if (_focusedDocId != null)
            TextButton.icon(
              icon: const Icon(Icons.public, size: 18),
              label: const Text('全庫圖譜'),
              onPressed: () {
                setState(() => _focusedDocId = null);
                _loadGraphData();
              },
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '重新排版圖譜',
            onPressed: _loadGraphData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _graph == null || _graph!.isEmpty
              ? const Center(child: Text('暫無文獻知識圖譜資料'))
              : Column(
                  children: [
                    // Statistics Banner
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                      child: Row(
                        children: [
                          Icon(Icons.hub, size: 18, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 8),
                          Text(
                            '實體節點：${_graph!.nodes.length} 個 • 關聯關係：${_graph!.edges.length} 條 • 文獻：${_documents.length} 篇',
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: KnowledgeGraphView(
                        graph: _graph!,
                        allDocuments: _documents,
                        onDocumentTap: _navigateToDoc,
                      ),
                    ),
                  ],
                ),
    );
  }
}
