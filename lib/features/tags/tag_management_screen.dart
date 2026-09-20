import 'dart:async';
import 'package:flutter/material.dart';
import 'package:smart_doc_search/core/theme/app_theme.dart';
import 'package:smart_doc_search/data/models/document_model.dart';
import 'package:smart_doc_search/data/repositories/document_repository.dart';
import 'package:uuid/uuid.dart';

class TagManagementScreen extends StatefulWidget {
  final DocumentRepository repository;

  const TagManagementScreen({super.key, required this.repository});

  @override
  State<TagManagementScreen> createState() => _TagManagementScreenState();
}

class _TagManagementScreenState extends State<TagManagementScreen> {
  StreamSubscription? _dataSub;
  List<TagDefinition> _tags = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadTags();
    _dataSub = widget.repository.onDataChanged.listen((_) {
      if (mounted) {
        _loadTags(showLoading: false);
      }
    });
  }

  @override
  void dispose() {
    _dataSub?.cancel();
    super.dispose();
  }

  Future<void> _loadTags({bool showLoading = true}) async {
    if (showLoading && _tags.isEmpty) {
      setState(() => _isLoading = true);
    }
    final list = await widget.repository.getAllTags();
    list.sort((a, b) => b.usageCount.compareTo(a.usageCount));
    if (mounted) {
      setState(() {
        _tags = list;
        _isLoading = false;
      });
    }
  }

  Future<void> _showAddOrEditTagDialog({TagDefinition? existing}) async {
    String name = existing?.name ?? '';
    String category = existing?.category ?? '主題';
    String aliasesText = existing?.aliases.join(', ') ?? '';

    final allCategories = [
      '主題', '領域', '方法', '對象', '結論', '文檔類型', '年份', '作者/機構',
      '醫學術語', '疾病/症狀', '疾病分類編碼'
    ];
    if (!allCategories.contains(category)) {
      allCategories.add(category);
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(existing == null ? '新增標籤' : '編輯標籤'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    autofocus: true,
                    controller: TextEditingController(text: name)..selection = TextSelection.collapsed(offset: name.length),
                    decoration: const InputDecoration(labelText: '標籤名稱', hintText: '例：機器學習'),
                    onChanged: (val) => name = val.trim(),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    decoration: const InputDecoration(labelText: '分類維度'),
                    items: allCategories
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setDialogState(() => category = val);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: TextEditingController(text: aliasesText)..selection = TextSelection.collapsed(offset: aliasesText.length),
                    decoration: const InputDecoration(
                      labelText: '同義詞 / 別名 (以逗號分隔)',
                      hintText: '例：ML, Machine Learning',
                    ),
                    onChanged: (val) => aliasesText = val.trim(),
                  ),
                ],
              ),
              actions: [
                if (existing != null)
                  TextButton.icon(
                    icon: const Icon(Icons.merge_type, size: 16),
                    label: const Text('合併此標籤'),
                    onPressed: () {
                      Navigator.pop(ctx, false);
                      _showMergeDialog(existing);
                    },
                  ),
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                ElevatedButton(
                  onPressed: () {
                    if (name.isNotEmpty) {
                      Navigator.pop(ctx, true);
                    }
                  },
                  child: const Text('儲存'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == true && name.isNotEmpty) {
      final aliases = aliasesText.split(RegExp(r'[,，]')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      final now = DateTime.now().millisecondsSinceEpoch;

      if (existing == null) {
        final newTag = TagDefinition(
          id: const Uuid().v4(),
          name: name,
          category: category,
          aliases: aliases,
          usageCount: 0,
          createdAt: now,
          updatedAt: now,
        );
        await widget.repository.updateTag(newTag);
      } else {
        final updated = existing.copyWith(
          name: name,
          category: category,
          aliases: aliases,
          updatedAt: now,
        );
        await widget.repository.updateTag(updated);
      }
      _loadTags();
    }
  }

  Future<void> _showMergeDialog(TagDefinition sourceTag) async {
    String targetTagName = '';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('合併標籤：#${sourceTag.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('將所有使用「#${sourceTag.name}」的文獻統一替換為指定之目標標籤，並刪除此來源標籤。'),
              const SizedBox(height: 14),
              TextField(
                autofocus: true,
                decoration: const InputDecoration(labelText: '目標標籤名稱', hintText: '輸入目標標籤名稱'),
                onChanged: (val) => targetTagName = val.trim(),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade800, foregroundColor: Colors.white),
              onPressed: () {
                if (targetTagName.isNotEmpty) {
                  Navigator.pop(ctx, true);
                }
              },
              child: const Text('確認合併'),
            ),
          ],
        );
      },
    );

    if (confirm == true && targetTagName.isNotEmpty) {
      await widget.repository.mergeTags(sourceTag.id, targetTagName);
      _loadTags();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已成功將 #${sourceTag.name} 合併至 #$targetTagName')),
        );
      }
    }
  }

  Future<void> _deleteTag(TagDefinition tag) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('刪除標籤確認'),
        content: Text('確定要刪除標籤「#${tag.name}」嗎？文獻中的該標籤記錄將同步移除。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('刪除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await widget.repository.deleteTag(tag.id);
      _loadTags();
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredTags = _tags.where((t) {
      if (_searchQuery.isEmpty) return true;
      return t.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          t.category.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('標籤管理', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新增標籤',
            onPressed: () => _showAddOrEditTagDialog(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search tag input
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              decoration: InputDecoration(
                hintText: '搜尋標籤或分類...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              onChanged: (val) => setState(() => _searchQuery = val.trim()),
            ),
          ),

          // Total Count
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('共 ${_tags.length} 個標籤', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
          ),

          const Divider(height: 1),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredTags.isEmpty
                    ? const Center(child: Text('查無標籤', style: TextStyle(color: Colors.grey)))
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final isTablet = constraints.maxWidth >= 720;
                          final isDark = Theme.of(context).brightness == Brightness.dark;

                          if (isTablet) {
                            return GridView.builder(
                              padding: const EdgeInsets.all(16),
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: constraints.maxWidth >= 1100 ? 3 : 2,
                                childAspectRatio: constraints.maxWidth >= 1100 ? 2.6 : 2.3,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                              ),
                              itemCount: filteredTags.length,
                              itemBuilder: (context, index) {
                                final tag = filteredTags[index];
                                return _buildGridTagCard(tag, isDark);
                              },
                            );
                          }

                          // Mobile single-column list
                          return ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: filteredTags.length,
                            itemBuilder: (context, index) {
                              final tag = filteredTags[index];

                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                clipBehavior: Clip.antiAlias,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.08)
                                        : Colors.black.withValues(alpha: 0.06),
                                  ),
                                ),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () => _showAddOrEditTagDialog(existing: tag),
                                  onLongPress: () => _showMergeDialog(tag),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        // 1. 分類維度標籤 (Leading)
                                        Container(
                                          constraints: const BoxConstraints(minWidth: 54),
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                                          decoration: BoxDecoration(
                                            color: AppTheme.getCategoryColor(tag.category).withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Center(
                                            child: Text(
                                              tag.category,
                                              maxLines: 1,
                                              style: TextStyle(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.bold,
                                                color: AppTheme.getCategoryColor(tag.category),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),

                                        // 2. 標籤文字 (雙行呈現、超出以...呈現、縮小標籤字體)
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Row(
                                                children: [
                                                  if (tag.codeSystem != null && tag.codeSystem!.isNotEmpty) ...[
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                                      margin: const EdgeInsets.only(right: 4),
                                                      decoration: BoxDecoration(
                                                        color: Colors.purple.withValues(alpha: 0.18),
                                                        borderRadius: BorderRadius.circular(4),
                                                      ),
                                                      child: Text(
                                                        tag.codeSystem!,
                                                        style: const TextStyle(
                                                          fontSize: 9.5,
                                                          fontWeight: FontWeight.bold,
                                                          color: Colors.purple,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                  Expanded(
                                                    child: Text(
                                                      tag.name,
                                                      maxLines: 2,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        fontWeight: FontWeight.w600,
                                                        fontSize: 13,
                                                        height: 1.25,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              if (tag.aliases.isNotEmpty) ...[
                                                const SizedBox(height: 2),
                                                Text(
                                                  '別名: ${tag.aliases.join(', ')}',
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 6),

                                        // 3. 固定在最右側：引用次數、編輯圖示、刪除圖示
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            // 引用次數
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: isDark
                                                    ? Colors.blueGrey.shade800.withValues(alpha: 0.6)
                                                    : Colors.grey.shade200,
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                '${tag.usageCount} 次引用',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w500,
                                                  color: isDark ? Colors.blueGrey.shade100 : Colors.grey.shade800,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 2),
                                            // 編輯圖示
                                            IconButton(
                                              icon: const Icon(Icons.edit_outlined, size: 18),
                                              tooltip: '編輯',
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                                              visualDensity: VisualDensity.compact,
                                              onPressed: () => _showAddOrEditTagDialog(existing: tag),
                                            ),
                                            // 刪除圖示
                                            IconButton(
                                              icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                                              tooltip: '刪除',
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                                              visualDensity: VisualDensity.compact,
                                              onPressed: () => _deleteTag(tag),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildGridTagCard(TagDefinition tag, bool isDark) {
    final catColor = AppTheme.getCategoryColor(tag.category);
    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.08),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _showAddOrEditTagDialog(existing: tag),
        onLongPress: () => _showMergeDialog(tag),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Top Row: Category Pill & code_system Pill & usageCount
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: catColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      tag.category,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: catColor,
                      ),
                    ),
                  ),
                  if (tag.codeSystem != null && tag.codeSystem!.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.purple.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        tag.codeSystem!,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.purple,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.blueGrey.shade800 : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${tag.usageCount} 次引用',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.blueGrey.shade100 : Colors.grey.shade800,
                      ),
                    ),
                  ),
                ],
              ),

              // Middle: Tag Name & Aliases
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tag.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      height: 1.25,
                    ),
                  ),
                  if (tag.aliases.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      '別名: ${tag.aliases.join(', ')}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ],
              ),

              // Bottom Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: const Icon(Icons.merge_type, size: 19),
                    tooltip: '合併此標籤',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: () => _showMergeDialog(tag),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 19),
                    tooltip: '編輯',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: () => _showAddOrEditTagDialog(existing: tag),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 19, color: Colors.redAccent),
                    tooltip: '刪除',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: () => _deleteTag(tag),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
