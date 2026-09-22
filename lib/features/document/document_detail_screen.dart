import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final bool isEmbedded;
  final VoidCallback? onDocumentDeleted;
  final VoidCallback? onDocumentUpdated;
  final int? initialPageNumber;
  final int initialTabIndex;

  const DocumentDetailScreen({
    super.key,
    required this.documentId,
    required this.repository,
    required this.ollamaClient,
    this.isEmbedded = false,
    this.onDocumentDeleted,
    this.onDocumentUpdated,
    this.initialPageNumber,
    this.initialTabIndex = 0,
  });

  @override
  State<DocumentDetailScreen> createState() => _DocumentDetailScreenState();
}

class _DocumentDetailScreenState extends State<DocumentDetailScreen> with SingleTickerProviderStateMixin {
  Document? _document;
  List<PageItem> _pages = [];
  bool _isLoading = true;
  late TabController _tabController;

  int _currentPageNumber = 1;
  bool _continuousTextView = false;

  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _inDocSearchCtrl = TextEditingController();
  String _inDocSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _currentPageNumber = (widget.initialPageNumber != null && widget.initialPageNumber! > 0)
        ? widget.initialPageNumber!
        : 1;
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
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
        if (_pages.isNotEmpty) {
          if (_currentPageNumber < 1 || _currentPageNumber > _pages.length) {
            _currentPageNumber = 1;
          }
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
    widget.onDocumentUpdated?.call();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('標題已更新')),
      );
    }
  }

  Future<void> _openOriginalFile([int? pageIndex]) async {
    if (_document == null) return;
    final copyPath = (_document!.metadata['documentsCopyPath'] as String?);
    final targetPath = (copyPath != null && copyPath.isNotEmpty) ? copyPath : _document!.filePath;
    final ok = await widget.repository.openFile(targetPath);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('系統未安裝第三方外部閱讀器，已自動為您切換至內建高解析版面檢視器'),
          duration: Duration(seconds: 3),
        ),
      );
      if (_pages.isNotEmpty) {
        _showFullscreenPageViewer(pageIndex ?? 0);
      }
    }
  }

  void _showFullscreenPageViewer(int initialIndex) {
    if (_pages.isEmpty) return;
    final validIndex = (initialIndex >= 0 && initialIndex < _pages.length) ? initialIndex : 0;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        int currentPage = validIndex;
        final pageCtrl = PageController(initialPage: validIndex);
        return StatefulBuilder(
          builder: (context, setViewerState) {
            final page = _pages[currentPage];
            return Dialog.fullscreen(
              child: Scaffold(
                appBar: AppBar(
                  title: Text('${_document?.title ?? "文獻"} (${currentPage + 1}/${_pages.length})'),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.open_in_new),
                      tooltip: '以系統外部程式開啟原始檔案',
                      onPressed: () => _openOriginalFile(currentPage),
                    ),
                  ],
                ),
                body: Column(
                  children: [
                    Expanded(
                      child: PageView.builder(
                        controller: pageCtrl,
                        itemCount: _pages.length,
                        onPageChanged: (idx) {
                          setViewerState(() => currentPage = idx);
                          if (mounted) {
                            setState(() => _currentPageNumber = idx + 1);
                          }
                        },
                        itemBuilder: (context, idx) {
                          final p = _pages[idx];
                          final hasImg = p.imagePath.isNotEmpty && File(p.imagePath).existsSync();
                          if (hasImg) {
                            return InteractiveViewer(
                              minScale: 0.5,
                              maxScale: 5.0,
                              child: Center(
                                child: Image.file(File(p.imagePath), fit: BoxFit.contain),
                              ),
                            );
                          } else {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: SingleChildScrollView(
                                  child: Text(
                                    p.ocrText.isEmpty ? '本頁暫無影像或辨識內容' : p.ocrText,
                                    style: const TextStyle(fontSize: 14, height: 1.6),
                                  ),
                                ),
                              ),
                            );
                          }
                        },
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.chevron_left),
                            tooltip: '上一頁',
                            onPressed: currentPage > 0
                                ? () => pageCtrl.previousPage(
                                      duration: const Duration(milliseconds: 250),
                                      curve: Curves.easeInOut,
                                    )
                                : null,
                          ),
                          Text(
                            '第 ${page.pageNumber} 頁 • 雙指縮放檢視原始版面細節',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                          ),
                          IconButton(
                            icon: const Icon(Icons.chevron_right),
                            tooltip: '下一頁',
                            onPressed: currentPage < _pages.length - 1
                                ? () => pageCtrl.nextPage(
                                      duration: const Duration(milliseconds: 250),
                                      curve: Curves.easeInOut,
                                    )
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
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
    widget.onDocumentUpdated?.call();
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
    widget.onDocumentUpdated?.call();
  }

  Future<void> _showAddTagDialog() async {
    String tagName = '';
    String category = '醫學術語';

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('新增結構化標籤'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: '標籤名稱',
                      hintText: '例：第2型糖尿病 / E11 / 胰島素阻抗',
                    ),
                    onChanged: (val) => tagName = val.trim(),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    decoration: const InputDecoration(labelText: '標籤維度'),
                    items: [
                      '醫學術語',
                      '疾病/症狀',
                      '疾病分類編碼',
                      '主題',
                      '領域',
                      '方法',
                      '對象',
                      '結論',
                      '文檔類型',
                      '年份',
                      '作者/機構',
                    ].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
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
      widget.onDocumentUpdated?.call();
    }
  }

  Future<void> _reAnalyzeWithAi() async {
    if (_document == null) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(width: 16),
                Text('呼叫 ${widget.ollamaClient.providerDisplayName} 深度分析中...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final allText = _pages.map((p) => '【第 ${p.pageNumber} 頁】\n${p.ocrText}').join('\n\n');
      final analysis = await widget.ollamaClient.generateAnalysis(
        text: '文獻標題：${_document!.title}\n\n完整全文內容：\n$allText',
      );

      if (mounted) {
        Navigator.pop(context); // Close loading dialog
      }

      if (analysis.tags.isNotEmpty || analysis.summary.isNotEmpty) {
        final userTags = _document!.tags.where((t) => t.source == 'user').toList();
        final combinedTags = [...userTags, ...analysis.tags];

        final updatedMetadata = Map<String, dynamic>.from(_document!.metadata);
        if (analysis.chineseSummary.isNotEmpty) {
          updatedMetadata['chineseSummary'] = analysis.chineseSummary;
        }

        final updated = _document!.copyWith(
          tags: combinedTags,
          summary: analysis.summary.isNotEmpty ? analysis.summary : _document!.summary,
          language: analysis.detectedLanguage.isNotEmpty ? analysis.detectedLanguage : _document!.language,
          metadata: updatedMetadata,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );

        await widget.repository.updateDocument(updated);
        setState(() => _document = updated);
        widget.onDocumentUpdated?.call();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('已透過 ${widget.ollamaClient.providerDisplayName} 成功更新醫學標籤與摘要！'),
              backgroundColor: Colors.teal,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('AI 服務未能解析有效標籤或摘要內容')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('AI 分析失敗: $e'), backgroundColor: Colors.red),
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
        if (widget.isEmbedded) {
          widget.onDocumentDeleted?.call();
        } else {
          Navigator.pop(context);
        }
      }
    }
  }

  void _copyAllOcrText() {
    final allOcr = _pages.map((p) => '【第 ${p.pageNumber} 頁】\n${p.ocrText}').join('\n\n');
    Clipboard.setData(ClipboardData(text: allOcr));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已複製全部文字內容至剪貼簿')),
    );
  }

  void _copyCurrentPageText(PageItem page) {
    Clipboard.setData(ClipboardData(text: page.ocrText));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已複製第 ${page.pageNumber} 頁文字內容至剪貼簿')),
    );
  }

  void _jumpToPage(int pageNumber) {
    if (_pages.isEmpty) return;
    final validPage = pageNumber.clamp(1, _pages.length);
    setState(() {
      _currentPageNumber = validPage;
      _continuousTextView = false;
    });
    _tabController.animateTo(0);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已為您定位至第 $validPage 頁文獻內容'),
        duration: const Duration(seconds: 2),
        action: SnackBarAction(
          label: '全螢幕',
          onPressed: () => _showFullscreenPageViewer(validPage - 1),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_document == null) {
      return Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !widget.isEmbedded,
          title: const Text('文獻詳情'),
        ),
        body: const Center(child: Text('找不到該文獻')),
      );
    }

    final doc = _document!;
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm');

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.isEmbedded,
        title: Text(
          widget.isEmbedded ? (doc.title.isNotEmpty ? doc.title : '文獻詳情') : '文獻詳情',
          style: const TextStyle(fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_new),
            tooltip: '直接開啟原始檔案',
            onPressed: () => _openOriginalFile(_currentPageNumber - 1),
          ),
          IconButton(
            icon: const Icon(Icons.auto_awesome_outlined),
            tooltip: '重新呼叫 AI 生成摘要與醫學標籤',
            onPressed: _reAnalyzeWithAi,
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
            Tab(text: '文獻內容', icon: Icon(Icons.article_outlined, size: 20)),
            Tab(text: '摘要與標籤', icon: Icon(Icons.description_outlined, size: 20)),
            Tab(text: '檔案元數據', icon: Icon(Icons.info_outline, size: 20)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: Prioritized Document Content & Targeted Page Layout
          _buildDocumentContentTab(doc),

          // Tab 2: AI Summary, Medical Tags & Title
          _buildSummaryAndTagsTab(doc),

          // Tab 3: Metadata
          _buildMetadataTab(doc, dateFormat),
        ],
      ),
    );
  }

  /// Tab 1: Prioritized Document Content & Direct Targeted Page Display
  Widget _buildDocumentContentTab(Document doc) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_pages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.description_outlined, size: 56, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              const Text('本文件暫無分頁文字內容', style: TextStyle(color: Colors.grey, fontSize: 16)),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.open_in_new),
                label: const Text('開啟原始檔案閱讀'),
                onPressed: () => _openOriginalFile(0),
              ),
            ],
          ),
        ),
      );
    }

    final currentPage = _pages.firstWhere(
      (p) => p.pageNumber == _currentPageNumber,
      orElse: () => _pages.first,
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 1. Highlight Banner if opened from Search with matched page
        if (widget.initialPageNumber != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F263D) : Colors.teal.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isDark ? Colors.teal.shade700 : Colors.teal.shade300,
                width: 1.2,
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.my_location, color: Colors.teal, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '【檢索定位命中】已直接呈現第 ${widget.initialPageNumber} 頁內容（省去翻頁尋找步驟）',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.teal.shade200 : Colors.teal.shade900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '您可點擊下方頁碼切換其他頁面，或切換為「連續全文」進行跨頁檢視。',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.teal.shade300 : Colors.teal.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // 2. Navigation & View Switcher Bar
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                // Previous page button
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  tooltip: '上一頁',
                  onPressed: (!_continuousTextView && _currentPageNumber > 1)
                      ? () => setState(() => _currentPageNumber--)
                      : null,
                ),

                // Current Page Badge / Selector
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _continuousTextView
                        ? '全篇連續全文 (共 ${_pages.length} 頁)'
                        : '第 $_currentPageNumber 頁 / 共 ${_pages.length} 頁',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),

                // Next page button
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  tooltip: '下一頁',
                  onPressed: (!_continuousTextView && _currentPageNumber < _pages.length)
                      ? () => setState(() => _currentPageNumber++)
                      : null,
                ),

                const Spacer(),

                // Toggle Continuous Text View
                ChoiceChip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(_continuousTextView ? Icons.view_headline : Icons.auto_stories, size: 14),
                  label: Text(_continuousTextView ? '切換分頁' : '連續全文', style: const TextStyle(fontSize: 11)),
                  selected: _continuousTextView,
                  onSelected: (val) => setState(() => _continuousTextView = val),
                ),
                const SizedBox(width: 8),

                // Open external / fullscreen
                IconButton(
                  icon: const Icon(Icons.fullscreen, size: 20),
                  tooltip: '全螢幕閱讀器',
                  onPressed: () => _showFullscreenPageViewer(_currentPageNumber - 1),
                ),
                IconButton(
                  icon: const Icon(Icons.open_in_new, size: 20),
                  tooltip: '以外部程式開啟原檔',
                  onPressed: () => _openOriginalFile(_currentPageNumber - 1),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // 3. Quick Jump Chips for all pages (P.1, P.2, P.3...)
        if (!_continuousTextView && _pages.length > 1) ...[
          SizedBox(
            height: 38,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _pages.length,
              itemBuilder: (context, idx) {
                final pageNum = _pages[idx].pageNumber;
                final isCurrent = pageNum == _currentPageNumber;
                final isSearchHit = pageNum == widget.initialPageNumber;

                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    visualDensity: VisualDensity.compact,
                    selected: isCurrent,
                    avatar: isSearchHit ? const Icon(Icons.bookmark, size: 13, color: Colors.teal) : null,
                    label: Text(
                      isSearchHit ? '第 $pageNum 頁 ★' : '第 $pageNum 頁',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isCurrent || isSearchHit ? FontWeight.bold : FontWeight.normal,
                        color: isCurrent ? null : (isSearchHit ? Colors.teal : null),
                      ),
                    ),
                    selectedColor: Theme.of(context).colorScheme.primaryContainer,
                    onSelected: (_) {
                      setState(() => _currentPageNumber = pageNum);
                    },
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
        ],

        // 4. In-document search box
        Card(
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: TextField(
              controller: _inDocSearchCtrl,
              decoration: InputDecoration(
                hintText: _continuousTextView ? '在連續全文中搜尋關鍵字...' : '在第 $_currentPageNumber 頁中搜尋關鍵字...',
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: _inDocSearchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () {
                          _inDocSearchCtrl.clear();
                          setState(() => _inDocSearchQuery = '');
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onChanged: (val) => setState(() => _inDocSearchQuery = val.trim()),
            ),
          ),
        ),

        const SizedBox(height: 14),

        // 5. Main Content: Page View vs Continuous Full Text
        if (_continuousTextView)
          _buildContinuousFullTextView(isDark)
        else
          _buildSinglePageView(currentPage, isDark),
      ],
    );
  }

  /// Single Page Content View with Image Preview, OCR Text, and Layout Blocks
  Widget _buildSinglePageView(PageItem page, bool isDark) {
    final hasImage = page.imagePath.isNotEmpty && File(page.imagePath).existsSync();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Image Preview (if available)
        if (hasImage) ...[
          Card(
            clipBehavior: Clip.antiAlias,
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: InkWell(
              onTap: () => _showFullscreenPageViewer(page.pageNumber - 1),
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  Image.file(
                    File(page.imagePath),
                    height: 260,
                    width: double.infinity,
                    fit: BoxFit.contain,
                  ),
                  Container(
                    margin: const EdgeInsets.all(8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.zoom_in, color: Colors.white, size: 14),
                        SizedBox(width: 4),
                        Text('點擊放大全螢幕檢視原始頁面', style: TextStyle(color: Colors.white, fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],

        // Page Text Content Card
        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.text_fields, color: isDark ? Colors.indigo.shade300 : Colors.indigo, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          '第 ${page.pageNumber} 頁全文內容 (OCR / 原生文字)',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ],
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.copy, size: 15),
                      label: const Text('複製本頁文字', style: TextStyle(fontSize: 12)),
                      onPressed: () => _copyCurrentPageText(page),
                    ),
                  ],
                ),
                const Divider(),
                const SizedBox(height: 6),
                Container(
                  constraints: const BoxConstraints(minHeight: 120, maxHeight: 500),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF090D14) : Colors.grey.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark ? Colors.blueGrey.shade800.withValues(alpha: 0.5) : Colors.grey.withValues(alpha: 0.2),
                    ),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      page.ocrText.isEmpty ? '本頁暫無文字內容' : page.ocrText,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.6,
                        fontFamily: 'monospace',
                        color: isDark ? const Color(0xFFE2E8F0) : null,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 14),

        // Layout Blocks (if present)
        if (page.layoutBlocks.isNotEmpty) ...[
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('版面結構分析區塊：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 8),
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
          ),
        ],
      ],
    );
  }

  /// Continuous Full Text View
  Widget _buildContinuousFullTextView(bool isDark) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '全篇連續全文 (全部頁面串接)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.copy_all, size: 16),
                  label: const Text('複製全篇全文', style: TextStyle(fontSize: 12)),
                  onPressed: _copyAllOcrText,
                ),
              ],
            ),
            const Divider(),
            ..._pages.map((p) {
              final isTargetPage = widget.initialPageNumber != null && p.pageNumber == widget.initialPageNumber;
              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isTargetPage
                      ? (isDark ? Colors.teal.shade900.withValues(alpha: 0.25) : Colors.teal.shade50.withValues(alpha: 0.6))
                      : (isDark ? const Color(0xFF090D14) : Colors.grey.withValues(alpha: 0.05)),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isTargetPage
                        ? Colors.teal
                        : (isDark ? Colors.blueGrey.shade800.withValues(alpha: 0.4) : Colors.grey.withValues(alpha: 0.2)),
                    width: isTargetPage ? 1.5 : 1.0,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isTargetPage ? Colors.teal : Colors.blueGrey,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            isTargetPage ? '第 ${p.pageNumber} 頁 (檢索命中)' : '第 ${p.pageNumber} 頁',
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.copy, size: 14),
                          label: const Text('複製本頁', style: TextStyle(fontSize: 11)),
                          onPressed: () => _copyCurrentPageText(p),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      p.ocrText.isEmpty ? '本頁無文字' : p.ocrText,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.55,
                        fontFamily: 'monospace',
                        color: isDark ? const Color(0xFFE2E8F0) : null,
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
  }

  /// Tab 2: AI Summary, Medical Tags & Title (Original Tab 0)
  Widget _buildSummaryAndTagsTab(Document doc) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chineseSummary = (doc.metadata['chineseSummary'] ?? '').toString().trim();
    final isEnglishDoc = doc.language.toLowerCase().startsWith('en') ||
        (chineseSummary.isNotEmpty && chineseSummary != doc.summary);

    // Group tags by category
    final tagsByCategory = <String, List<TagItem>>{};
    for (final tag in doc.tags) {
      tagsByCategory.putIfAbsent(tag.category, () => []).add(tag);
    }

    final sortedCategories = tagsByCategory.keys.toList()
      ..sort((a, b) {
        const priority = {'疾病/症狀': 0, '疾病分類編碼': 1, '醫學術語': 2, '主題': 3, '領域': 4, '方法': 5};
        final pa = priority[a] ?? 10;
        final pb = priority[b] ?? 10;
        return pa.compareTo(pb);
      });

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 1. Prominent AI Executive Summary Card
        _buildAiSummaryCard(doc, chineseSummary, isEnglishDoc, isDark),

        const SizedBox(height: 14),

        // 2. Editable Document Title Card
        Card(
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.title, color: Colors.blueGrey, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _titleCtrl,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: '文獻標題',
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.check_circle, color: Colors.green),
                  tooltip: '儲存標題',
                  onPressed: _saveTitle,
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 14),

        // 3. Medical & Structured Tags Card
        _buildMedicalTagsCard(doc, sortedCategories, tagsByCategory),
      ],
    );
  }

  /// Prominent AI Summary Box
  Widget _buildAiSummaryCard(Document doc, String chineseSummary, bool isEnglishDoc, bool isDark) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isDark ? Colors.blue.withValues(alpha: 0.35) : Colors.blue.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            colors: isDark
                ? [
                    const Color(0xFF0F1523),
                    const Color(0xFF14192B),
                  ]
                : [
                    Colors.blue.withValues(alpha: 0.07),
                    Colors.purple.withValues(alpha: 0.04),
                  ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome, color: Colors.amber, size: 22),
                const SizedBox(width: 8),
                const Text(
                  'AI 智能文獻摘要',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.indigo.shade900.withValues(alpha: 0.5) : Colors.indigo.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: isDark ? Border.all(color: Colors.indigo.shade400.withValues(alpha: 0.3)) : null,
                  ),
                  child: Text(
                    widget.ollamaClient.providerDisplayName,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.indigo.shade200 : Colors.indigo,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0A2220) : Colors.teal.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDark ? Colors.teal.shade700.withValues(alpha: 0.5) : Colors.teal.shade200,
                  width: 0.8,
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.track_changes, color: isDark ? Colors.teal.shade300 : Colors.teal, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '目標檢索確認：請閱讀下方摘要，快速判斷是否為您查詢之目標文獻。',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.teal.shade200 : Colors.teal.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            if (isEnglishDoc && chineseSummary.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF141006) : Colors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark ? Colors.amber.shade700.withValues(alpha: 0.55) : Colors.amber.shade700.withValues(alpha: 0.4),
                    width: 1.0,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.translate, size: 16, color: isDark ? Colors.amber.shade300 : Colors.amber.shade800),
                        const SizedBox(width: 6),
                        Text(
                          '英文文獻中文摘要說明',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.amber.shade200 : Colors.amber.shade900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _buildBulletSummaryView(chineseSummary, isChinese: true, isDark: isDark),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            if (doc.summary.isNotEmpty && doc.summary != chineseSummary) ...[
              Text(
                '文獻核心主旨與重點（條列式）：',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.blueGrey.shade200 : Colors.blueGrey.shade800,
                ),
              ),
              const SizedBox(height: 6),
              _buildBulletSummaryView(doc.summary, isChinese: false, isDark: isDark),
            ] else if (doc.summary.isNotEmpty && chineseSummary.isEmpty) ...[
              _buildBulletSummaryView(doc.summary, isChinese: false, isDark: isDark),
            ],

            const SizedBox(height: 12),
            const Divider(),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('重新 AI 生成摘要與標籤', style: TextStyle(fontSize: 12)),
                  onPressed: _reAnalyzeWithAi,
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('開啟原始檔案', style: TextStyle(fontSize: 12)),
                  onPressed: () => _openOriginalFile(_currentPageNumber - 1),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBulletSummaryView(String summaryText, {bool isChinese = false, required bool isDark}) {
    if (summaryText.trim().isEmpty) {
      return const Text('無摘要內容', style: TextStyle(color: Colors.grey));
    }

    final rawLines = summaryText.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rawLines.map((line) {
        final pageRegex = RegExp(r'(\(|【)(P\.?\s*([0-9]+)|第\s*([0-9]+)\s*頁)(\)|】)', caseSensitive: false);
        final matches = pageRegex.allMatches(line);

        int? targetPage;
        if (matches.isNotEmpty) {
          final m = matches.first;
          final pageStr = m.group(3) ?? m.group(4);
          if (pageStr != null) {
            targetPage = int.tryParse(pageStr);
          }
        }

        final itemBgColor = isDark
            ? (isChinese ? const Color(0xFF0C0904) : const Color(0xFF090D15))
            : (isChinese ? Colors.amber.shade50.withValues(alpha: 0.85) : Colors.blueGrey.shade50.withValues(alpha: 0.75));

        final itemBorderColor = isDark
            ? (isChinese ? Colors.amber.shade800.withValues(alpha: 0.45) : Colors.blueGrey.shade800.withValues(alpha: 0.6))
            : (isChinese ? Colors.amber.shade200 : Colors.blueGrey.shade200);

        final itemTextColor = isDark
            ? (isChinese ? const Color(0xFFFFFBEB) : const Color(0xFFF8FAFC))
            : (isChinese ? const Color(0xFF451A03) : const Color(0xFF0F172A));

        final arrowColor = isDark
            ? (isChinese ? Colors.amber.shade400 : AppTheme.secondaryColor)
            : (isChinese ? Colors.amber.shade800 : AppTheme.primaryColor);

        final chipBgColor = isDark
            ? (isChinese ? const Color(0xFF2B1D06) : const Color(0xFF0F263D))
            : (isChinese ? Colors.amber.shade100 : AppTheme.primaryColor.withValues(alpha: 0.12));

        final chipBorderColor = isDark
            ? (isChinese ? Colors.amber.shade600.withValues(alpha: 0.6) : AppTheme.primaryColor.withValues(alpha: 0.6))
            : (isChinese ? Colors.amber.shade300 : AppTheme.primaryColor.withValues(alpha: 0.35));

        final chipTextColor = isDark
            ? (isChinese ? Colors.amber.shade200 : Colors.lightBlue.shade200)
            : (isChinese ? Colors.brown.shade800 : AppTheme.primaryColor);

        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: itemBgColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: itemBorderColor,
              width: 0.8,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 6),
                child: Icon(
                  Icons.arrow_right,
                  size: 16,
                  color: arrowColor,
                ),
              ),
              Expanded(
                child: SelectableText(
                  line,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    fontWeight: FontWeight.w400,
                    color: itemTextColor,
                  ),
                ),
              ),
              if (targetPage != null) ...[
                const SizedBox(width: 6),
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => _jumpToPage(targetPage!),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: chipBgColor,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: chipBorderColor),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.menu_book, size: 11, color: chipTextColor),
                        const SizedBox(width: 3),
                        Text(
                          'P.$targetPage',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: chipTextColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildMedicalTagsCard(
    Document doc,
    List<String> sortedCategories,
    Map<String, List<TagItem>> tagsByCategory,
  ) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.medical_services_outlined, color: Colors.teal, size: 20),
                    SizedBox(width: 8),
                    Text(
                      '專業醫學標籤分類 (按維度)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ],
                ),
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
                child: Text('暫無標籤，可點擊上方按鈕手動新增或使用 AI 重新辨識。', style: TextStyle(color: Colors.grey)),
              )
            else
              ...sortedCategories.map((category) {
                final tags = tagsByCategory[category] ?? [];
                final color = AppTheme.getCategoryColor(category);

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            category,
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '(${tags.length})',
                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final maxLabelWidth = (constraints.maxWidth - 70).clamp(100.0, 1000.0);
                          return Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: tags.map((t) {
                              return InputChip(
                                label: ConstrainedBox(
                                  constraints: BoxConstraints(maxWidth: maxLabelWidth),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (t.codeSystem != null && t.codeSystem!.isNotEmpty) ...[
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                          margin: const EdgeInsets.only(right: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.purple.withValues(alpha: 0.18),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            t.codeSystem!,
                                            style: const TextStyle(
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.purple,
                                            ),
                                          ),
                                        ),
                                      ],
                                      Flexible(
                                        child: Text(
                                          '${t.name} (${(t.confidence * 100).toInt()}%)',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                avatar: Icon(
                                  t.verified ? Icons.verified : Icons.help_outline,
                                  size: 16,
                                  color: t.verified ? Colors.blue : Colors.orange,
                                ),
                                selected: t.verified,
                                onSelected: (_) => _toggleTagVerified(t),
                                onDeleted: () => _deleteTag(t),
                                tooltip: '代碼系統: ${t.codeSystem ?? "無"} • 點擊審核狀態（${t.verified ? '已審核' : '待審核'}）• 來源: ${t.source}',
                              );
                            }).toList(),
                          );
                        },
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  /// Tab 3: Metadata Tab
  Widget _buildMetadataTab(Document doc, DateFormat dateFormat) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('文獻元數據與檔案資訊', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    IconButton(
                      icon: const Icon(Icons.open_in_new),
                      tooltip: '開啟原始檔案',
                      onPressed: () => _openOriginalFile(_currentPageNumber - 1),
                    ),
                  ],
                ),
                const Divider(),
                _buildMetaRow('檔案格式', doc.sourceType.toUpperCase()),
                _buildMetaRow('總頁數', '${doc.pageCount} 頁'),
                _buildMetaRow('語言識別', doc.language),
                if (doc.metadata['extractionMethod'] != null)
                  _buildMetaRow(
                    '文字解析方式',
                    doc.metadata['extractionMethod'] == 'native_text'
                        ? '原生文字內容直接判讀（跳過 OCR）'
                        : '端側 OCR 文字識別',
                  ),
                _buildMetaRow('匯入時間', dateFormat.format(DateTime.fromMillisecondsSinceEpoch(doc.createdAt))),
                _buildMetaRow('最後更新', dateFormat.format(DateTime.fromMillisecondsSinceEpoch(doc.updatedAt))),
                _buildMetaRow('SHA-256 查重碼', doc.fileHash.isNotEmpty ? doc.fileHash : '無'),
                _buildMetaRow('文獻存放路徑', (doc.metadata['documentsCopyPath'] as String?) ?? doc.filePath),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.file_open),
                    label: const Text('以外部檢視器開啟原始檔案'),
                    onPressed: () => _openOriginalFile(_currentPageNumber - 1),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMetaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey))),
          Expanded(
            child: SelectableText(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}
