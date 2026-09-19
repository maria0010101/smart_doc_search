import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:smart_doc_search/core/theme/app_theme.dart';
import 'package:smart_doc_search/data/datasources/ollama_client.dart';
import 'package:smart_doc_search/data/models/document_model.dart';
import 'package:smart_doc_search/data/repositories/document_repository.dart';
import 'package:uuid/uuid.dart';

class DocumentDetailScreen extends StatefulWidget {
  final String documentId;
  final DocumentRepository repository;
  final OllamaClient ollamaClient;

  const DocumentDetailScreen({
    super.key,
    required this.documentId,
    required this.repository,
    required this.ollamaClient,
  });

  @override
  State<DocumentDetailScreen> createState() => _DocumentDetailScreenState();
}

class _DocumentDetailScreenState extends State<DocumentDetailScreen> with SingleTickerProviderStateMixin {
  Document? _document;
  List<PageItem> _pages = [];
  bool _isLoading = true;
  late TabController _tabController;

  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _inDocSearchCtrl = TextEditingController();
  String _inDocSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadDocumentDetails();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _titleCtrl.dispose();
    _inDocSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDocumentDetails() async {
    setState(() => _isLoading = true);
    final doc = await widget.repository.getDocument(widget.documentId);
    final pages = await widget.repository.getDocumentPages(widget.documentId);

    if (mounted) {
      setState(() {
        _document = doc;
        _pages = pages;
        _isLoading = false;
        if (doc != null) {
          _titleCtrl.text = doc.title;
        }
      });
    }
  }

  Future<void> _saveTitle() async {
    if (_document == null) return;
    final newTitle = _titleCtrl.text.trim();
    if (newTitle.isEmpty || newTitle == _document!.title) return;

    final updated = _document!.copyWith(
      title: newTitle,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await widget.repository.updateDocument(updated);
    setState(() => _document = updated);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('標題已更新')),
      );
    }
  }

  Future<void> _toggleTagVerified(TagItem tag) async {
    if (_document == null) return;
    final updatedTags = _document!.tags.map((t) {
      if (t.id == tag.id) {
        return t.copyWith(verified: !t.verified);
      }
      return t;
    }).toList();

    final updated = _document!.copyWith(
      tags: updatedTags,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await widget.repository.updateDocument(updated);
    setState(() => _document = updated);
  }

  Future<void> _deleteTag(TagItem tag) async {
    if (_document == null) return;
    final updatedTags = _document!.tags.where((t) => t.id != tag.id).toList();
    final updated = _document!.copyWith(
      tags: updatedTags,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await widget.repository.updateDocument(updated);
    setState(() => _document = updated);
  }

  Future<void> _showAddTagDialog() async {
    String tagName = '';
    String category = '主題';

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('新增自訂標籤'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(labelText: '標籤名稱', hintText: '例：機器學習'),
                    onChanged: (val) => tagName = val.trim(),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    decoration: const InputDecoration(labelText: '標籤維度'),
                    items: ['主題', '領域', '方法', '對象', '結論', '文檔類型', '年份', '作者/機構']
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setDialogState(() => category = val);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
                ElevatedButton(
                  onPressed: () {
                    if (tagName.isNotEmpty) {
                      Navigator.pop(context, true);
                    }
                  },
                  child: const Text('新增'),
                ),
              ],
            );
          },
        );
      },
    );

    if (tagName.isNotEmpty && _document != null) {
      final newTag = TagItem(
        id: const Uuid().v4(),
        name: tagName,
        category: category,
        confidence: 1.0,
        source: 'user',
        verified: true,
      );

      final updatedTags = [..._document!.tags, newTag];
      final updated = _document!.copyWith(
        tags: updatedTags,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await widget.repository.updateDocument(updated);
      setState(() => _document = updated);
    }
  }

  Future<void> _reTagWithOllama() async {
    if (_document == null) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Text('呼叫 Ollama 重新生成標籤...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final allText = _pages.map((p) => p.ocrText).join('\n');
      final newTags = await widget.ollamaClient.generateTags(
        text: '${_document!.title}\n$allText',
      );

      if (mounted) {
        Navigator.pop(context); // Close loading dialog
      }

      if (newTags.isNotEmpty) {
        // Keep existing user-added tags
        final userTags = _document!.tags.where((t) => t.source == 'user').toList();
        final combined = [...userTags, ...newTags];

        final updated = _document!.copyWith(
          tags: combined,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );
        await widget.repository.updateDocument(updated);
        setState(() => _document = updated);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已成功生成 ${newTags.length} 個新標籤！')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ollama 未能解析標籤或無內容回應')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('標籤生成失敗: $e')),
        );
      }
    }
  }

  Future<void> _confirmDeleteDocument() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('刪除確認'),
        content: const Text('確定要刪除這份文獻及其所有頁面資料嗎？此動作無法復原。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('確定刪除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await widget.repository.deleteDocument(widget.documentId);
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_document == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('文獻詳情')),
        body: const Center(child: Text('找不到該文獻')),
      );
    }

    final doc = _document!;
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm');

    return Scaffold(
      appBar: AppBar(
        title: const Text('文獻詳情', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.psychology_outlined),
            tooltip: '重新呼叫 Ollama 生成標籤',
            onPressed: _reTagWithOllama,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            tooltip: '刪除文獻',
            onPressed: _confirmDeleteDocument,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '標籤與元數據', icon: Icon(Icons.label_outline, size: 20)),
            Tab(text: 'OCR 全文', icon: Icon(Icons.text_snippet_outlined, size: 20)),
            Tab(text: '頁面版面', icon: Icon(Icons.auto_stories_outlined, size: 20)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: Tags & Metadata
          _buildTagsAndMetadataTab(doc, dateFormat),

          // Tab 2: OCR Fulltext
          _buildOcrTextTab(),

          // Tab 3: Pages & Layout Blocks
          _buildPagesLayoutTab(),
        ],
      ),
    );
  }

  Widget _buildTagsAndMetadataTab(Document doc, DateFormat dateFormat) {
    // Group tags by category
    final tagsByCategory = <String, List<TagItem>>{};
    for (final tag in doc.tags) {
      tagsByCategory.putIfAbsent(tag.category, () => []).add(tag);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Editable Title Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('文獻標題', style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _titleCtrl,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        decoration: const InputDecoration(border: InputBorder.none),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.check, color: Colors.green),
                      tooltip: '儲存標題',
                      onPressed: _saveTitle,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Tags Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('多維結構化標籤 (AI / 人工審核)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline, color: AppTheme.primaryColor),
                      tooltip: '新增標籤',
                      onPressed: _showAddTagDialog,
                    ),
                  ],
                ),
                const Divider(),
                if (doc.tags.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('暫無標籤，可點擊上方按鈕手動新增或使用 Ollama AI 生成。', style: TextStyle(color: Colors.grey)),
                  )
                else
                  ...tagsByCategory.entries.map((entry) {
                    final category = entry.key;
                    final tags = entry.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(category, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.getCategoryColor(category))),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: tags.map((t) {
                              return InputChip(
                                label: Text('${t.name} (${(t.confidence * 100).toInt()}%)'),
                                avatar: Icon(
                                  t.verified ? Icons.verified : Icons.help_outline,
                                  size: 16,
                                  color: t.verified ? Colors.blue : Colors.orange,
                                ),
                                selected: t.verified,
                                onSelected: (_) => _toggleTagVerified(t),
                                onDeleted: () => _deleteTag(t),
                                tooltip: '點擊切換審核狀態（${t.verified ? '已審核' : '待審核'}）• 來源: ${t.source}',
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Metadata Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('文獻元數據', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const Divider(),
                _buildMetaRow('檔案格式', doc.sourceType.toUpperCase()),
                _buildMetaRow('頁數', '${doc.pageCount} 頁'),
                _buildMetaRow('語言', doc.language),
                _buildMetaRow('匯入時間', dateFormat.format(DateTime.fromMillisecondsSinceEpoch(doc.createdAt))),
                _buildMetaRow('最後更新', dateFormat.format(DateTime.fromMillisecondsSinceEpoch(doc.updatedAt))),
                _buildMetaRow('SHA-256 查重碼', doc.fileHash.isNotEmpty ? doc.fileHash : '無'),
                _buildMetaRow('原始檔案路徑', doc.filePath),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMetaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 100, child: Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  Widget _buildOcrTextTab() {
    final allOcr = _pages.map((p) => '【第 ${p.pageNumber} 頁】\n${p.ocrText}').join('\n\n');

    return Column(
      children: [
        // In-document search bar
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _inDocSearchCtrl,
            decoration: InputDecoration(
              hintText: '在此篇文獻內搜尋關鍵字...',
              prefixIcon: const Icon(Icons.find_in_page),
              suffixIcon: _inDocSearchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _inDocSearchCtrl.clear();
                        setState(() => _inDocSearchQuery = '');
                      },
                    )
                  : null,
              filled: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
            onChanged: (val) => setState(() => _inDocSearchQuery = val.trim()),
          ),
        ),

        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SingleChildScrollView(
              child: SelectableText(
                allOcr.isEmpty ? '尚無文字識別內容' : allOcr,
                style: const TextStyle(fontSize: 14, height: 1.6),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPagesLayoutTab() {
    if (_pages.isEmpty) {
      return const Center(child: Text('無分頁資料'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _pages.length,
      itemBuilder: (context, index) {
        final page = _pages[index];
        final hasImage = page.imagePath.isNotEmpty && File(page.imagePath).existsSync();

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '第 ${page.pageNumber} 頁',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),

                // Image Thumbnail if available
                if (hasImage) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(page.imagePath),
                      height: 200,
                      width: double.infinity,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Layout Blocks Section
                const Text('版面分析區塊：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                if (page.layoutBlocks.isEmpty)
                  Text(page.ocrText, style: const TextStyle(fontSize: 12, color: Colors.grey))
                else
                  ...page.layoutBlocks.map((block) {
                    Color typeColor = Colors.grey;
                    if (block.type == 'title') typeColor = Colors.blue;
                    if (block.type == 'table') typeColor = Colors.green;
                    if (block.type == 'footer') typeColor = Colors.orange;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: typeColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: typeColor.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(color: typeColor, borderRadius: BorderRadius.circular(4)),
                            child: Text(
                              block.type.toUpperCase(),
                              style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              block.text,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        );
      },
    );
  }
}
