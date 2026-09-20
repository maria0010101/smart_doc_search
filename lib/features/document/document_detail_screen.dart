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

  const DocumentDetailScreen({
    super.key,
    required this.documentId,
    required this.repository,
    required this.ollamaClient,
    this.isEmbedded = false,
    this.onDocumentDeleted,
    this.onDocumentUpdated,
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
        // Keep existing user-added tags
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
            onPressed: _openOriginalFile,
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
            Tab(text: '摘要與標籤內文', icon: Icon(Icons.description_outlined, size: 20)),
            Tab(text: '頁面版面', icon: Icon(Icons.auto_stories_outlined, size: 20)),
            Tab(text: '檔案元數據', icon: Icon(Icons.info_outline, size: 20)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: AI Summary, Medical Tags & Recognized Text Content
          _buildSummaryAndRecognizedContentTab(doc),

          // Tab 2: Page Layout Blocks & Open Original File
          _buildPagesLayoutTab(doc),

          // Tab 3: Metadata
          _buildMetadataTab(doc, dateFormat),
        ],
      ),
    );
  }

  /// Tab 1: AI Summary at very top, followed by Medical/Structured Tags and Full Recognized Content
  Widget _buildSummaryAndRecognizedContentTab(Document doc) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chineseSummary = (doc.metadata['chineseSummary'] ?? '').toString().trim();
    final isEnglishDoc = doc.language.toLowerCase().startsWith('en') ||
        (chineseSummary.isNotEmpty && chineseSummary != doc.summary);

    // Group tags by category
    final tagsByCategory = <String, List<TagItem>>{};
    for (final tag in doc.tags) {
      tagsByCategory.putIfAbsent(tag.category, () => []).add(tag);
    }

    // Prioritized Medical Dimensions First
    final sortedCategories = tagsByCategory.keys.toList()
      ..sort((a, b) {
        const priority = {'疾病/症狀': 0, '疾病分類編碼': 1, '醫學術語': 2, '主題': 3, '領域': 4, '方法': 5};
        final pa = priority[a] ?? 10;
        final pb = priority[b] ?? 10;
        return pa.compareTo(pb);
      });

    final allOcrText = _pages.map((p) => '【第 ${p.pageNumber} 頁】\n${p.ocrText}').join('\n\n');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 1. Prominent AI Executive Summary Card (置於最上方確認是否為查詢目標)
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

        // 3. Medical & Structured Tags Card (醫學術語、疾病/症狀、疾病分類編碼等)
        _buildMedicalTagsCard(doc, sortedCategories, tagsByCategory),

        const SizedBox(height: 14),

        // 4. Recognized Text Content (辨識後文字內容呈現)
        _buildRecognizedTextSection(allOcrText, isDark),
      ],
    );
  }

  /// Prominent AI Summary Box at top
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
            // Header with AI Provider Badge and Actions
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

            // Target Document Verification Guidance Banner
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

            // English Document -> Highlighted Chinese Summary Section (英文文獻增加中文摘要說明)
            if (isEnglishDoc && chineseSummary.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF141006) // 加深底色：深琥珀黑底色，形成極佳明暗對比
                      : Colors.amber.withValues(alpha: 0.12),
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

            // Full Executive Summary
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

            // Action row: Re-analyze or Open File
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
                  onPressed: _openOriginalFile,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Builds dynamic bullet-point summary cards with clickable source page citations
  Widget _buildBulletSummaryView(String summaryText, {bool isChinese = false, required bool isDark}) {
    if (summaryText.trim().isEmpty) {
      return const Text('無摘要內容', style: TextStyle(color: Colors.grey));
    }

    final rawLines = summaryText.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rawLines.map((line) {
        // Extract page reference like (P.1), (P. 2), 【P.1】, 【第 1 頁】
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

        // 深色模式加深底色，文字採用清晰明亮高對比配色
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

  void _jumpToPage(int pageNumber) {
    if (_pages.isEmpty) return;
    final pageIndex = (pageNumber - 1).clamp(0, _pages.length - 1);
    _tabController.animateTo(1);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已跳轉至第 $pageNumber 頁版面'),
        duration: const Duration(seconds: 2),
        action: SnackBarAction(
          label: '開啟全螢幕檢視',
          onPressed: () => _showFullscreenPageViewer(pageIndex),
        ),
      ),
    );
  }

  /// Medical & Structured Tags Card
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

  /// Recognized Text Content Section
  Widget _buildRecognizedTextSection(String allOcrText, bool isDark) {
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
                Row(
                  children: [
                    Icon(Icons.text_snippet_outlined, color: isDark ? Colors.indigo.shade300 : Colors.indigo, size: 20),
                    const SizedBox(width: 8),
                    const Text('辨識後文字內容 (OCR)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ],
                ),
                TextButton.icon(
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('複製全文', style: TextStyle(fontSize: 12)),
                  onPressed: _copyAllOcrText,
                ),
              ],
            ),
            const SizedBox(height: 8),

            // In-document Search Input
            TextField(
              controller: _inDocSearchCtrl,
              decoration: InputDecoration(
                hintText: '在辨識內文搜尋關鍵字或醫學術語...',
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
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onChanged: (val) => setState(() => _inDocSearchQuery = val.trim()),
            ),

            const SizedBox(height: 12),

            // Extracted / Recognized text display
            Container(
              constraints: const BoxConstraints(maxHeight: 450),
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
                  allOcrText.isEmpty ? '尚無文字識別內容' : allOcrText,
                  style: TextStyle(
                    fontSize: 13,
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
    );
  }

  /// Tab 2: Page Layout Blocks & Direct Link to Open Original File (頁面版面直接連結開啟原始檔案)
  Widget _buildPagesLayoutTab(Document doc) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Prominent Direct Link to Open Original File (頁面版面直接連結開啟原始檔案)
        Card(
          color: Colors.indigo.shade50.withValues(alpha: 0.1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.indigo.withValues(alpha: 0.3)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.file_present, color: Colors.indigo, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '原始檔案：${doc.title}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '格式: ${doc.sourceType.toUpperCase()} • 頁數: ${doc.pageCount} 頁',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('直接開啟原始檔案 (外部閱讀器)', style: TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: () => _openOriginalFile(0),
                      ),
                    ),
                    if (_pages.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.fullscreen),
                        label: const Text('全螢幕檢視'),
                        onPressed: () => _showFullscreenPageViewer(0),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Per-page Layout Analysis Cards
        if (_pages.isEmpty)
          const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('無分頁版面資料')))
        else
          ..._pages.map((page) {
            final hasImage = page.imagePath.isNotEmpty && File(page.imagePath).existsSync();
            final pageIndex = _pages.indexOf(page);

            return Card(
              margin: const EdgeInsets.only(bottom: 16),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '第 ${page.pageNumber} 頁版面',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        Row(
                          children: [
                            TextButton.icon(
                              icon: const Icon(Icons.fullscreen, size: 14),
                              label: const Text('全螢幕', style: TextStyle(fontSize: 12)),
                              onPressed: () => _showFullscreenPageViewer(pageIndex),
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.open_in_new, size: 14),
                              label: const Text('開啟原檔', style: TextStyle(fontSize: 12)),
                              onPressed: () => _openOriginalFile(pageIndex),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Image Thumbnail if available (tap to open fullscreen viewer)
                    if (hasImage) ...[
                      InkWell(
                        onTap: () => _showFullscreenPageViewer(pageIndex),
                        borderRadius: BorderRadius.circular(8),
                        child: Stack(
                          alignment: Alignment.bottomRight,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(
                                File(page.imagePath),
                                height: 220,
                                width: double.infinity,
                                fit: BoxFit.contain,
                              ),
                            ),
                            Container(
                              margin: const EdgeInsets.all(8),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.65),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.zoom_in, color: Colors.white, size: 14),
                                  SizedBox(width: 4),
                                  Text('點擊放大版面', style: TextStyle(color: Colors.white, fontSize: 11)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Layout Blocks Section
                    const Text('版面結構分析區塊：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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
          }),
      ],
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
                      onPressed: _openOriginalFile,
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
                    onPressed: _openOriginalFile,
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
