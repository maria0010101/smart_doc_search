import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:smart_doc_search/core/theme/app_theme.dart';
import 'package:smart_doc_search/data/datasources/ollama_client.dart';
import 'package:smart_doc_search/data/models/document_model.dart';
import 'package:smart_doc_search/data/repositories/document_repository.dart';
import 'package:smart_doc_search/features/document/document_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  final DocumentRepository repository;
  final OllamaClient ollamaClient;
  final Function(int) onNavigateTab;
  final Function(String) onQuickSearch;

  const HomeScreen({
    super.key,
    required this.repository,
    required this.ollamaClient,
    required this.onNavigateTab,
    required this.onQuickSearch,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<Document> _recentDocs = [];
  Map<String, dynamic> _stats = {};
  bool _isLoading = true;
  bool? _ollamaOnline;

  @override
  void initState() {
    super.initState();
    _loadData();
    _checkOllama();
  }

  Future<void> _checkOllama() async {
    final online = await widget.ollamaClient.testConnection();
    if (mounted) {
      setState(() => _ollamaOnline = online);
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final docs = await widget.repository.getAllDocuments();
    final stats = await widget.repository.getStorageStats();

    // Sort by recent updated
    docs.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    if (mounted) {
      setState(() {
        _recentDocs = docs.take(10).toList();
        _stats = stats;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm');

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.auto_stories, color: AppTheme.primaryColor),
            const SizedBox(width: 8),
            const Text(
              '個人智能文獻檢索',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        actions: [
          // Ollama status chip
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Tooltip(
              message: _ollamaOnline == true
                  ? 'Ollama 服務在線 (${widget.ollamaClient.host})'
                  : 'Ollama 離線（仍可離線全文檢索）',
              child: Chip(
                avatar: Icon(
                  Icons.circle,
                  size: 10,
                  color: _ollamaOnline == true ? Colors.green : Colors.grey,
                ),
                label: Text(
                  _ollamaOnline == true ? 'AI 在線' : '離線模式',
                  style: const TextStyle(fontSize: 11),
                ),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadData();
          await _checkOllama();
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Quick Search Box
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: '搜尋文獻標題、標籤、OCR 全文...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: () {
                    if (_searchCtrl.text.trim().isNotEmpty) {
                      widget.onQuickSearch(_searchCtrl.text.trim());
                    }
                  },
                ),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (val) {
                if (val.trim().isNotEmpty) {
                  widget.onQuickSearch(val.trim());
                }
              },
            ),

            const SizedBox(height: 16),

            // Statistics Grid
            Row(
              children: [
                _buildStatCard('文獻總數', '${_stats['documentCount'] ?? 0}', Icons.description, Colors.blue),
                const SizedBox(width: 10),
                _buildStatCard('頁面總數', '${_stats['pageCount'] ?? 0}', Icons.layers, Colors.teal),
                const SizedBox(width: 10),
                _buildStatCard('標籤總數', '${_stats['tagCount'] ?? 0}', Icons.label, Colors.purple),
              ],
            ),

            const SizedBox(height: 20),

            // Quick Import Banner
            Card(
              color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.upload_file, color: Theme.of(context).colorScheme.primary, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '匯入新文獻',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '支援 PDF、圖片（JPG/PNG/WebP）端側 OCR 與 AI 標籤',
                            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => widget.onNavigateTab(2), // Jump to Import Tab
                      child: const Text('匯入'),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Recent Documents Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '最近文獻',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                if (_recentDocs.isNotEmpty)
                  TextButton(
                    onPressed: () => widget.onNavigateTab(1), // Go to search
                    child: const Text('查看全部'),
                  ),
              ],
            ),

            const SizedBox(height: 8),

            if (_isLoading)
              const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
            else if (_recentDocs.isEmpty)
              Container(
                padding: const EdgeInsets.all(32),
                alignment: Alignment.center,
                child: Column(
                  children: [
                    Icon(Icons.folder_open, size: 56, color: Colors.grey.shade400),
                    const SizedBox(height: 12),
                    const Text('尚未匯入任何文獻', style: TextStyle(color: Colors.grey)),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => widget.onNavigateTab(2),
                      icon: const Icon(Icons.add),
                      label: const Text('立即匯入文獻'),
                    ),
                  ],
                ),
              )
            else
              ..._recentDocs.map((doc) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (ctx) => DocumentDetailScreen(
                            documentId: doc.id,
                            repository: widget.repository,
                            ollamaClient: widget.ollamaClient,
                          ),
                        ),
                      );
                      _loadData();
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSourceTypeIcon(doc.sourceType),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      doc.title,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${dateFormat.format(DateTime.fromMillisecondsSinceEpoch(doc.updatedAt))} • ${doc.pageCount} 頁',
                                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (doc.summary.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              doc.summary,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                            ),
                          ],
                          if (doc.tags.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: doc.tags.take(4).map((tag) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTheme.getCategoryColor(tag.category).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    tag.name,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.getCategoryColor(tag.category),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color ?? Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.1)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 2),
            Text(title, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }

  Widget _buildSourceTypeIcon(String type) {
    IconData icon;
    Color color;
    switch (type.toLowerCase()) {
      case 'pdf':
        icon = Icons.picture_as_pdf;
        color = Colors.red;
        break;
      case 'ppt':
      case 'pptx':
        icon = Icons.slideshow;
        color = Colors.orange;
        break;
      default:
        icon = Icons.image;
        color = Colors.blue;
    }
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }
}
