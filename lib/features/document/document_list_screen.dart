import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:smart_doc_search/core/theme/app_theme.dart';
import 'package:smart_doc_search/data/datasources/ollama_client.dart';
import 'package:smart_doc_search/data/models/document_model.dart';
import 'package:smart_doc_search/data/repositories/document_repository.dart';
import 'package:smart_doc_search/features/document/document_detail_screen.dart';
import 'package:smart_doc_search/features/import/import_screen.dart';
import 'package:smart_doc_search/features/import/import_service.dart';

enum DocumentSortOption {
  newestUpdated,
  newestCreated,
  titleAsc,
  pageCountDesc,
}

class DocumentListScreen extends StatefulWidget {
  final DocumentRepository repository;
  final OllamaClient ollamaClient;
  final ImportService? importService;
  final Function(String)? onQuickSearch;
  final VoidCallback? onOpenImport;

  const DocumentListScreen({
    super.key,
    required this.repository,
    required this.ollamaClient,
    this.importService,
    this.onQuickSearch,
    this.onOpenImport,
  });

  @override
  State<DocumentListScreen> createState() => _DocumentListScreenState();
}

class _DocumentListScreenState extends State<DocumentListScreen> {
  final TextEditingController _filterCtrl = TextEditingController();
  StreamSubscription? _dataSub;
  List<Document> _allDocuments = [];
  List<Document> _filteredDocuments = [];
  bool _isLoading = true;
  DocumentSortOption _sortOption = DocumentSortOption.newestUpdated;
  String? _selectedCategory;
  String? _selectedDocId;

  @override
  void initState() {
    super.initState();
    _loadDocuments();
    _dataSub = widget.repository.onDataChanged.listen((_) {
      if (mounted) {
        _loadDocuments(showLoading: false);
      }
    });
  }

  @override
  void dispose() {
    _dataSub?.cancel();
    _filterCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDocuments({bool showLoading = true}) async {
    if (showLoading && _allDocuments.isEmpty) {
      setState(() => _isLoading = true);
    }
    final docs = await widget.repository.getAllDocuments();
    if (mounted) {
      setState(() {
        _allDocuments = docs;
        _applyFilterAndSort();
        _isLoading = false;

        // On wide screens, auto-select first document if nothing is selected or if previous was deleted
        if (_filteredDocuments.isNotEmpty) {
          if (_selectedDocId == null || !_filteredDocuments.any((d) => d.id == _selectedDocId)) {
            _selectedDocId = _filteredDocuments.first.id;
          }
        } else {
          _selectedDocId = null;
        }
      });
    }
  }

  void _applyFilterAndSort() {
    final query = _filterCtrl.text.trim().toLowerCase();
    List<Document> list = _allDocuments.where((doc) {
      final matchesQuery = query.isEmpty ||
          doc.title.toLowerCase().contains(query) ||
          doc.summary.toLowerCase().contains(query) ||
          doc.tags.any((t) => t.name.toLowerCase().contains(query));

      final matchesCategory = _selectedCategory == null ||
          doc.tags.any((t) => t.category == _selectedCategory);

      return matchesQuery && matchesCategory;
    }).toList();

    switch (_sortOption) {
      case DocumentSortOption.newestUpdated:
        list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        break;
      case DocumentSortOption.newestCreated:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case DocumentSortOption.titleAsc:
        list.sort((a, b) => a.title.compareTo(b.title));
        break;
      case DocumentSortOption.pageCountDesc:
        list.sort((a, b) => b.pageCount.compareTo(a.pageCount));
        break;
    }

    _filteredDocuments = list;
  }

  Future<void> _renameDocument(Document doc) async {
    final editCtrl = TextEditingController(text: doc.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.edit_note, color: AppTheme.primaryColor),
              SizedBox(width: 8),
              Text('修改文獻名稱'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('請輸入新的文獻標題名稱：', style: TextStyle(fontSize: 13)),
              const SizedBox(height: 10),
              TextField(
                controller: editCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: '輸入文獻標題...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () {
                final text = editCtrl.text.trim();
                if (text.isNotEmpty) {
                  Navigator.pop(ctx, text);
                }
              },
              child: const Text('確認更名'),
            ),
          ],
        );
      },
    );

    if (newTitle != null && newTitle.isNotEmpty && newTitle != doc.title) {
      final updated = doc.copyWith(
        title: newTitle,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await widget.repository.updateDocument(updated);
      _loadDocuments();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已成功將文獻更名為「$newTitle」'),
            backgroundColor: Colors.teal,
          ),
        );
      }
    }
  }

  Future<void> _deleteDocument(Document doc) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('刪除確認'),
          ],
        ),
        content: Text('確定要刪除這份文獻及其所有頁面資料嗎？\n\n文獻名稱：${doc.title}\n此動作無法復原。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('確定刪除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await widget.repository.deleteDocument(doc.id);
      if (_selectedDocId == doc.id) {
        setState(() => _selectedDocId = null);
      }
      _loadDocuments();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已刪除文獻「${doc.title}」'),
            action: SnackBarAction(
              label: '確定',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
    }
  }

  void _openImportScreen() async {
    if (widget.onOpenImport != null) {
      widget.onOpenImport!();
      return;
    }
    if (widget.importService != null) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (ctx) => ImportScreen(
            importService: widget.importService!,
            onImportSuccess: () {
              widget.repository.notifyDataChanged(immediate: true);
            },
          ),
        ),
      );
      _loadDocuments();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isTablet = constraints.maxWidth >= 720;

        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                const Icon(Icons.folder_copy_outlined, color: AppTheme.primaryColor),
                const SizedBox(width: 8),
                const Text('文獻清單', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_filteredDocuments.length}/${_allDocuments.length}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                tooltip: '匯入新文獻',
                onPressed: _openImportScreen,
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: '重新整理',
                onPressed: () => _loadDocuments(),
              ),
            ],
          ),
          body: isTablet
              ? _buildTabletLayout(constraints)
              : _buildMobileLayout(),
        );
      },
    );
  }

  Widget _buildTabletLayout(BoxConstraints constraints) {
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Left column: document list & search filter
        SizedBox(
          width: constraints.maxWidth >= 1050 ? 460 : 380,
          child: Column(
            children: [
              _buildFilterAndSortHeader(),
              const Divider(height: 1),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _filteredDocuments.isEmpty
                        ? _buildEmptyState()
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            itemCount: _filteredDocuments.length,
                            itemBuilder: (context, index) {
                              final doc = _filteredDocuments[index];
                              return _buildDocumentCard(doc, dateFormat, isTablet: true);
                            },
                          ),
              ),
            ],
          ),
        ),

        const VerticalDivider(width: 1, thickness: 1),

        // Right column: embedded detail view
        Expanded(
          child: _selectedDocId != null
              ? DocumentDetailScreen(
                  key: ValueKey(_selectedDocId),
                  documentId: _selectedDocId!,
                  repository: widget.repository,
                  ollamaClient: widget.ollamaClient,
                  isEmbedded: true,
                  onDocumentDeleted: () {
                    setState(() => _selectedDocId = null);
                    _loadDocuments();
                  },
                  onDocumentUpdated: _loadDocuments,
                )
              : _buildTabletEmptyPlaceholder(),
        ),
      ],
    );
  }

  Widget _buildMobileLayout() {
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm');

    return Column(
      children: [
        _buildFilterAndSortHeader(),
        const Divider(height: 1),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _filteredDocuments.isEmpty
                  ? _buildEmptyState()
                  : RefreshIndicator(
                      onRefresh: () => _loadDocuments(),
                      child: ListView.builder(
                        padding: const EdgeInsets.all(14),
                        itemCount: _filteredDocuments.length,
                        itemBuilder: (context, index) {
                          final doc = _filteredDocuments[index];
                          return _buildDocumentCard(doc, dateFormat, isTablet: false);
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildFilterAndSortHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        children: [
          TextField(
            controller: _filterCtrl,
            decoration: InputDecoration(
              hintText: '搜尋文獻標題、摘要、標籤...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _filterCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _filterCtrl.clear();
                        setState(() => _applyFilterAndSort());
                      },
                    )
                  : null,
              filled: true,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (_) => setState(() => _applyFilterAndSort()),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                const Text('排序: ', style: TextStyle(fontSize: 11, color: Colors.grey)),
                PopupMenuButton<DocumentSortOption>(
                  initialValue: _sortOption,
                  child: Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: const Icon(Icons.sort, size: 14),
                    label: Text(_getSortOptionName(_sortOption), style: const TextStyle(fontSize: 11)),
                  ),
                  onSelected: (opt) {
                    setState(() {
                      _sortOption = opt;
                      _applyFilterAndSort();
                    });
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: DocumentSortOption.newestUpdated,
                      child: Text('最近修改'),
                    ),
                    const PopupMenuItem(
                      value: DocumentSortOption.newestCreated,
                      child: Text('最新匯入'),
                    ),
                    const PopupMenuItem(
                      value: DocumentSortOption.titleAsc,
                      child: Text('標題 (A-Z)'),
                    ),
                    const PopupMenuItem(
                      value: DocumentSortOption.pageCountDesc,
                      child: Text('頁數最多'),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
                if (_selectedCategory != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InputChip(
                      visualDensity: VisualDensity.compact,
                      label: Text('維度: $_selectedCategory', style: const TextStyle(fontSize: 11)),
                      onDeleted: () {
                        setState(() {
                          _selectedCategory = null;
                          _applyFilterAndSort();
                        });
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getSortOptionName(DocumentSortOption opt) {
    switch (opt) {
      case DocumentSortOption.newestUpdated:
        return '最近修改';
      case DocumentSortOption.newestCreated:
        return '最新匯入';
      case DocumentSortOption.titleAsc:
        return '標題 (A-Z)';
      case DocumentSortOption.pageCountDesc:
        return '頁數最多';
    }
  }

  Widget _buildDocumentCard(Document doc, DateFormat dateFormat, {required bool isTablet}) {
    final isSelected = isTablet && doc.id == _selectedDocId;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: isSelected ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected
            ? const BorderSide(color: AppTheme.primaryColor, width: 2)
            : BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.1)),
      ),
      color: isSelected
          ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.25)
          : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          if (isTablet) {
            setState(() => _selectedDocId = doc.id);
          } else {
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
            _loadDocuments();
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Icon, Title & Action Menu
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
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: isSelected ? AppTheme.primaryColor : null,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${dateFormat.format(DateTime.fromMillisecondsSinceEpoch(doc.updatedAt))} • ${doc.pageCount} 頁 • ${doc.sourceType.toUpperCase()}',
                          style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: '文獻管理選項',
                    icon: const Icon(Icons.more_vert, size: 20),
                    onSelected: (val) {
                      if (val == 'rename') {
                        _renameDocument(doc);
                      } else if (val == 'delete') {
                        _deleteDocument(doc);
                      } else if (val == 'open') {
                        widget.repository.openFile(doc.filePath);
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                        value: 'rename',
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined, size: 18, color: Colors.blue),
                            SizedBox(width: 8),
                            Text('修改文獻名稱'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'open',
                        child: Row(
                          children: [
                            Icon(Icons.open_in_new, size: 18, color: Colors.indigo),
                            SizedBox(width: 8),
                            Text('開啟原始檔案'),
                          ],
                        ),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, size: 18, color: Colors.red),
                            SizedBox(width: 8),
                            Text('刪除文獻', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // Summary
              if (doc.summary.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  doc.summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey.shade300
                        : Colors.grey.shade700,
                  ),
                ),
              ],

              // Tags
              if (doc.tags.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: doc.tags.take(5).map((tag) {
                    final color = AppTheme.getCategoryColor(tag.category);
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        tag.name,
                        style: TextStyle(
                          fontSize: 11,
                          color: color,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],

              // Quick action buttons footer
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    icon: const Icon(Icons.edit, size: 14),
                    label: const Text('更名', style: TextStyle(fontSize: 11.5)),
                    onPressed: () => _renameDocument(doc),
                  ),
                  const SizedBox(width: 4),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    icon: const Icon(Icons.delete_outline, size: 14),
                    label: const Text('刪除', style: TextStyle(fontSize: 11.5)),
                    onPressed: () => _deleteDocument(doc),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text(
              '尚無文獻或無符合條件之文獻',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            const Text(
              '可點擊下方按鈕匯入 PDF 或圖片，系統將自動解析文字與 AI 標籤。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('立即匯入文獻'),
              onPressed: _openImportScreen,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabletEmptyPlaceholder() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.folder_special_outlined,
                size: 64,
                color: AppTheme.primaryColor,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '選取文獻檢視詳情與編輯',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '請由左側列表點擊任意文獻，即可在此瀏覽全文、頁面版面，或進行名稱修改與刪除。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
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
