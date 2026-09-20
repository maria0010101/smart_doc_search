import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:smart_doc_search/core/theme/app_theme.dart';
import 'package:smart_doc_search/data/datasources/ollama_client.dart';
import 'package:smart_doc_search/data/models/document_model.dart';
import 'package:smart_doc_search/data/repositories/document_repository.dart';
import 'package:smart_doc_search/features/document/document_detail_screen.dart';
import 'package:smart_doc_search/features/search/hybrid_search_service.dart';

class SearchScreen extends StatefulWidget {
  final DocumentRepository repository;
  final OllamaClient ollamaClient;
  final HybridSearchService searchService;
  final String? initialQuery;

  const SearchScreen({
    super.key,
    required this.repository,
    required this.ollamaClient,
    required this.searchService,
    this.initialQuery,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchCtrl = TextEditingController();

  List<TagDefinition> _allTags = [];
  final Set<String> _selectedTags = {};
  String _tagMode = 'AND'; // 'AND' | 'OR'
  bool _enableSemanticSearch = true;
  SearchSortOrder _sortOrder = SearchSortOrder.relevance;
  final Set<String> _fileTypeFilters = {}; // 'pdf', 'image', 'ppt'

  SearchResult? _searchResult;
  bool _isSearching = false;
  bool _expandedTabletTags = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery != null) {
      _searchCtrl.text = widget.initialQuery!;
    }
    _loadTags();
    _performSearch();
  }

  Future<void> _loadTags() async {
    final tags = await widget.repository.getAllTags();
    if (mounted) {
      setState(() => _allTags = tags);
    }
  }

  Future<void> _performSearch() async {
    setState(() => _isSearching = true);
    try {
      final res = await widget.searchService.executeSearch(
        queryText: _searchCtrl.text.trim(),
        selectedTags: _selectedTags.toList(),
        tagMode: _tagMode,
        enableSemanticSearch: _enableSemanticSearch,
        fileTypeFilters: _fileTypeFilters.toList(),
        sortOrder: _sortOrder,
      );
      if (mounted) {
        setState(() {
          _searchResult = res;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  void _clearAllFilters() {
    setState(() {
      _selectedTags.clear();
      _fileTypeFilters.clear();
      _sortOrder = SearchSortOrder.relevance;
      _enableSemanticSearch = true;
    });
    _performSearch();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isTablet = constraints.maxWidth >= 720;

        return Scaffold(
          appBar: AppBar(
            title: const Text('文獻檢索', style: TextStyle(fontWeight: FontWeight.bold)),
            actions: [
              if (isTablet && (_selectedTags.isNotEmpty || _fileTypeFilters.isNotEmpty))
                TextButton.icon(
                  icon: const Icon(Icons.clear_all, size: 18),
                  label: const Text('重設篩選'),
                  onPressed: _clearAllFilters,
                ),
              IconButton(
                icon: const Icon(Icons.filter_list),
                tooltip: '進階篩選與排序',
                onPressed: _showFilterDialog,
              ),
            ],
          ),
          body: isTablet
              ? _buildTabletSearchLayout(constraints)
              : _buildMobileSearchLayout(),
        );
      },
    );
  }

  /// Tablet Dual-Pane Search: Top Search Conditions + Bottom Dual-Column Result List
  Widget _buildTabletSearchLayout(BoxConstraints constraints) {
    return Column(
      children: [
        // 1. 上方搜尋條件 (Top Search Conditions Panel)
        Card(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Search Input Row
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: InputDecoration(
                          hintText: '輸入關鍵字、醫學術語、疾病編碼或語義問題...',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    _performSearch();
                                  },
                                )
                              : null,
                          filled: true,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onSubmitted: (_) => _performSearch(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.search, size: 18),
                      label: const Text('檢索'),
                      onPressed: _performSearch,
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // Tags Condition Row / Wrap
                if (_allTags.isNotEmpty) ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ActionChip(
                        avatar: Icon(_tagMode == 'AND' ? Icons.all_inclusive : Icons.alt_route, size: 14),
                        label: Text(
                          _tagMode == 'AND' ? '模式: 符合全部標籤 (AND)' : '模式: 符合任一標籤 (OR)',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          setState(() => _tagMode = _tagMode == 'AND' ? 'OR' : 'AND');
                          _performSearch();
                        },
                      ),
                      ...(_expandedTabletTags ? _allTags : _allTags.take(12)).map((tag) {
                        final isSelected = _selectedTags.contains(tag.name);
                        return FilterChip(
                          visualDensity: VisualDensity.compact,
                          selected: isSelected,
                          label: Text(
                            '${tag.name} (${tag.usageCount})',
                            style: const TextStyle(fontSize: 11),
                          ),
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                _selectedTags.add(tag.name);
                              } else {
                                _selectedTags.remove(tag.name);
                              }
                            });
                            _performSearch();
                          },
                          selectedColor: AppTheme.getCategoryColor(tag.category).withValues(alpha: 0.2),
                          checkmarkColor: AppTheme.getCategoryColor(tag.category),
                        );
                      }),
                      if (_allTags.length > 12)
                        TextButton(
                          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                          onPressed: () => setState(() => _expandedTabletTags = !_expandedTabletTags),
                          child: Text(_expandedTabletTags ? '收合' : '更多標籤 (${_allTags.length})...', style: const TextStyle(fontSize: 11)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],

                // Filter & Sort Settings Bar
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      // Semantic Toggle
                      FilterChip(
                        visualDensity: VisualDensity.compact,
                        avatar: const Icon(Icons.psychology, size: 14),
                        label: const Text('AI 語義向量檢索', style: TextStyle(fontSize: 11)),
                        selected: _enableSemanticSearch,
                        onSelected: (val) {
                          setState(() => _enableSemanticSearch = val);
                          _performSearch();
                        },
                      ),
                      const SizedBox(width: 8),

                      // File Types
                      const Text('格式: ', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      ...['pdf', 'image', 'ppt'].map((type) {
                        final isSel = _fileTypeFilters.contains(type);
                        return Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: FilterChip(
                            visualDensity: VisualDensity.compact,
                            label: Text(type.toUpperCase(), style: const TextStyle(fontSize: 10)),
                            selected: isSel,
                            onSelected: (selected) {
                              setState(() {
                                if (selected) {
                                  _fileTypeFilters.add(type);
                                } else {
                                  _fileTypeFilters.remove(type);
                                }
                              });
                              _performSearch();
                            },
                          ),
                        );
                      }),
                      const SizedBox(width: 8),

                      // Sort Order
                      const Text('排序: ', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      ...[
                        MapEntry(SearchSortOrder.relevance, '相關度'),
                        MapEntry(SearchSortOrder.newestImport, '最新匯入'),
                        MapEntry(SearchSortOrder.newestModified, '最近修改'),
                        MapEntry(SearchSortOrder.title, '標題'),
                      ].map((entry) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: ChoiceChip(
                            visualDensity: VisualDensity.compact,
                            label: Text(entry.value, style: const TextStyle(fontSize: 10)),
                            selected: _sortOrder == entry.key,
                            onSelected: (_) {
                              setState(() => _sortOrder = entry.key);
                              _performSearch();
                            },
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // Search Status Metadata
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _searchResult != null ? '找到 ${_searchResult!.total} 份文獻' : '檢索中...',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
              ),
              if (_searchResult != null)
                Text(
                  '耗時 ${_searchResult!.tookMs} ms • 雙欄自適應檢索 • 混合權重 (詞 0.4 + 向量 0.4 + 標籤 0.2)',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
            ],
          ),
        ),

        const Divider(height: 1),

        // 2. 下方結果列表 (Bottom Dual-Column Results List)
        Expanded(
          child: _isSearching
              ? const Center(child: CircularProgressIndicator())
              : (_searchResult == null || _searchResult!.items.isEmpty)
                  ? _buildEmptyResultsView()
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Left Column
                          Expanded(
                            child: Column(
                              children: [
                                for (int i = 0; i < _searchResult!.items.length; i += 2)
                                  _buildDocumentHitCard(_searchResult!.items[i]),
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),
                          // Right Column
                          Expanded(
                            child: Column(
                              children: [
                                for (int i = 1; i < _searchResult!.items.length; i += 2)
                                  _buildDocumentHitCard(_searchResult!.items[i]),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
        ),
      ],
    );
  }

  /// Mobile Single-Column Search Layout
  Widget _buildMobileSearchLayout() {
    return Column(
      children: [
        // Search Bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: '輸入關鍵字或語義問題...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_searchCtrl.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        _performSearch();
                      },
                    ),
                  IconButton(
                    icon: const Icon(Icons.arrow_forward),
                    onPressed: _performSearch,
                  ),
                ],
              ),
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            onSubmitted: (_) => _performSearch(),
          ),
        ),

        // Tag Filter Bar
        if (_allTags.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                // AND/OR Toggle Chip
                ActionChip(
                  label: Text(_tagMode == 'AND' ? '模式: 全部符合 (AND)' : '模式: 任一符合 (OR)'),
                  avatar: Icon(_tagMode == 'AND' ? Icons.all_inclusive : Icons.alt_route, size: 16),
                  onPressed: () {
                    setState(() {
                      _tagMode = _tagMode == 'AND' ? 'OR' : 'AND';
                    });
                    _performSearch();
                  },
                ),
                const SizedBox(width: 8),
                // Tag chips
                ..._allTags.take(15).map((tag) {
                  final isSelected = _selectedTags.contains(tag.name);
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      selected: isSelected,
                      label: Text('${tag.name} (${tag.usageCount})'),
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedTags.add(tag.name);
                          } else {
                            _selectedTags.remove(tag.name);
                          }
                        });
                        _performSearch();
                      },
                      selectedColor: AppTheme.getCategoryColor(tag.category).withValues(alpha: 0.2),
                      checkmarkColor: AppTheme.getCategoryColor(tag.category),
                    ),
                  );
                }),
              ],
            ),
          ),

        // Search Meta Status
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _searchResult != null ? '找到 ${_searchResult!.total} 份文獻' : '檢索中...',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              if (_searchResult != null)
                Text(
                  '耗時 ${_searchResult!.tookMs} ms • 混合權重 (詞 0.4 + 向量 0.4 + 標籤 0.2)',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
            ],
          ),
        ),

        const Divider(height: 1),

        // Search Results List
        Expanded(
          child: _isSearching
              ? const Center(child: CircularProgressIndicator())
              : (_searchResult == null || _searchResult!.items.isEmpty)
                  ? _buildEmptyResultsView()
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _searchResult!.items.length,
                      itemBuilder: (context, index) {
                        final hit = _searchResult!.items[index];
                        return _buildDocumentHitCard(hit);
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildEmptyResultsView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          const Text('查無符合條件之文獻', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 6),
          const Text('請嘗試更換關鍵字、取消部分標籤或篩選器', style: TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildDocumentHitCard(DocumentHit hit) {
    final doc = hit.document;
    final scorePercent = (hit.score * 100).clamp(0, 100).toStringAsFixed(0);
    final dateFormat = DateFormat('yyyy-MM-dd');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
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
          _performSearch();
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title & Score Badge
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSourceBadge(doc.sourceType),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      doc.title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.secondaryColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$scorePercent% 相關度',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.secondaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),

              // Highlight snippet
              if (hit.highlight != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.format_quote, size: 16, color: Colors.amber),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          hit.highlight!,
                          style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Summary
              if (hit.highlight == null && doc.summary.isNotEmpty) ...[
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
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: doc.tags.take(6).map((tag) {
                    final isMatched = hit.matchedTags.contains(tag.name);
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isMatched
                            ? AppTheme.accentColor.withValues(alpha: 0.2)
                            : AppTheme.getCategoryColor(tag.category).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: isMatched ? Border.all(color: AppTheme.accentColor, width: 0.8) : null,
                      ),
                      child: Text(
                        '#${tag.name}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isMatched ? FontWeight.bold : FontWeight.normal,
                          color: isMatched ? Colors.amber.shade900 : AppTheme.getCategoryColor(tag.category),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],

              const SizedBox(height: 8),

              // Footer Meta
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${dateFormat.format(DateTime.fromMillisecondsSinceEpoch(doc.createdAt))} • ${doc.pageCount} 頁 • ${doc.language}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                  Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSourceBadge(String type) {
    Color c = Colors.blue;
    if (type == 'pdf') c = Colors.red;
    if (type == 'ppt') c = Colors.orange;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        type.toUpperCase(),
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: c),
      ),
    );
  }

  void _showFilterDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('進階篩選與檢索設定', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                    ],
                  ),
                  const Divider(),

                  // Semantic search toggle
                  SwitchListTile(
                    title: const Text('啟用 AI 語義向量檢索'),
                    subtitle: const Text('透過 Ollama 向量模型匹配相關語義概念'),
                    value: _enableSemanticSearch,
                    onChanged: (val) {
                      setSheetState(() => _enableSemanticSearch = val);
                      setState(() => _enableSemanticSearch = val);
                    },
                  ),

                  const SizedBox(height: 8),

                  // File Types Filter
                  const Text('文件格式篩選：', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: ['pdf', 'image', 'ppt'].map((type) {
                      final isSelected = _fileTypeFilters.contains(type);
                      return FilterChip(
                        label: Text(type.toUpperCase()),
                        selected: isSelected,
                        onSelected: (selected) {
                          setSheetState(() {
                            if (selected) {
                              _fileTypeFilters.add(type);
                            } else {
                              _fileTypeFilters.remove(type);
                            }
                          });
                          setState(() {});
                        },
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 16),

                  // Sorting
                  const Text('排序方式：', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('相關度排序'),
                        selected: _sortOrder == SearchSortOrder.relevance,
                        onSelected: (_) {
                          setSheetState(() => _sortOrder = SearchSortOrder.relevance);
                          setState(() => _sortOrder = SearchSortOrder.relevance);
                        },
                      ),
                      ChoiceChip(
                        label: const Text('最新匯入'),
                        selected: _sortOrder == SearchSortOrder.newestImport,
                        onSelected: (_) {
                          setSheetState(() => _sortOrder = SearchSortOrder.newestImport);
                          setState(() => _sortOrder = SearchSortOrder.newestImport);
                        },
                      ),
                      ChoiceChip(
                        label: const Text('最近修改'),
                        selected: _sortOrder == SearchSortOrder.newestModified,
                        onSelected: (_) {
                          setSheetState(() => _sortOrder = SearchSortOrder.newestModified);
                          setState(() => _sortOrder = SearchSortOrder.newestModified);
                        },
                      ),
                      ChoiceChip(
                        label: const Text('標題排序'),
                        selected: _sortOrder == SearchSortOrder.title,
                        onSelected: (_) {
                          setSheetState(() => _sortOrder = SearchSortOrder.title);
                          setState(() => _sortOrder = SearchSortOrder.title);
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _performSearch();
                      },
                      child: const Text('套用篩選'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
