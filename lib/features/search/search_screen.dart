import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:smart_doc_search/core/services/knowledge_graph_service.dart';
import 'package:smart_doc_search/core/theme/app_theme.dart';
import 'package:smart_doc_search/data/datasources/ollama_client.dart';
import 'package:smart_doc_search/data/models/document_model.dart';
import 'package:smart_doc_search/data/repositories/document_repository.dart';
import 'package:smart_doc_search/features/document/document_detail_screen.dart';
import 'package:smart_doc_search/features/graph/knowledge_graph_screen.dart';
import 'package:smart_doc_search/features/search/hybrid_search_service.dart';
import 'package:smart_doc_search/features/search/search_query_parser.dart';

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
  final KnowledgeGraphService _graphService = KnowledgeGraphService();
  StreamSubscription? _dataSub;

  List<TagDefinition> _allTags = [];
  List<Document> _allDocuments = [];
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
    _dataSub = widget.repository.onDataChanged.listen((_) {
      if (mounted) {
        _loadTags();
        _performSearch();
      }
    });
  }

  @override
  void dispose() {
    _dataSub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTags() async {
    final tags = await widget.repository.getAllTags();
    final docs = await widget.repository.getAllDocuments();
    if (mounted) {
      setState(() {
        _allTags = tags;
        _allDocuments = docs;
      });
    }
  }

  Future<void> _performSearch() async {
    setState(() => _isSearching = true);
    try {
      final res = await widget.searchService.executeSearch(
        queryText: _searchCtrl.text.trim(),
        selectedTags: _selectedTags.toList(),
        tagMode: _tagMode,
        requireAllKeywords: _tagMode == 'AND',
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

  /// Displays the supported search operators together with concrete examples.
  void _showSearchSyntaxHelp() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('進階搜尋語法'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: const [
              Text('支援與主流搜尋引擎相同的前置運算子：',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              SizedBox(height: 12),
              _SyntaxRow(
                operator: '+',
                title: '必須包含（AND）',
                example: '糖尿病+心血管',
                description: '以 + 連結前後關鍵字時，結果必須同時包含所有關鍵字。',
              ),
              _SyntaxRow(
                operator: '-',
                title: '排除（NOT）',
                example: '糖尿病 -動物實驗',
                description: '以 - 標註關鍵字時，結果會排除包含該關鍵字的文獻。',
              ),
              _SyntaxRow(
                operator: '空白',
                title: '一般關鍵字（OR）',
                example: '糖尿病 心血管',
                description: '以空白分隔的關鍵字為選用詞，僅影響排序權重，不需全部命中。',
              ),
              SizedBox(height: 4),
              Text('組合範例：糖尿病+心血管 -動物實驗', style: TextStyle(fontSize: 12.5)),
              SizedBox(height: 6),
              Text('※ 切換鈕「全部符合」會把上面所有一般關鍵字都視為必須包含；'
                  '「任一符合」則只需命中其中一個。', style: TextStyle(fontSize: 12)),
              SizedBox(height: 4),
              Text('※ COVID-19、IL-6 等連字號詞彙不會被誤判為排除運算子。',
                  style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('了解'),
          ),
        ],
      ),
    );
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
                icon: const Icon(Icons.hub_outlined),
                tooltip: '開啟知識圖譜視覺化',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => KnowledgeGraphScreen(
                        repository: widget.repository,
                        ollamaClient: widget.ollamaClient,
                      ),
                    ),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.help_outline),
                tooltip: '搜尋語法說明 (+ / -)',
                onPressed: _showSearchSyntaxHelp,
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
                          hintText: '輸入多個關鍵字（空白分隔），亦可使用 + 必要詞、- 排除詞',
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
                          _tagMode == 'AND' ? '關鍵字+標籤: 全部符合 (AND)' : '關鍵字+標籤: 任一符合 (OR)',
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
              hintText: '輸入多個關鍵字（空白分隔），亦可使用 + 必要詞、- 排除詞',
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

        // Parsed operator feedback (+ required / - excluded)
        Builder(builder: (context) {
          final parsed =
              SearchQueryParser.parse(_searchCtrl.text, requireAll: _tagMode == 'AND');
          if (!parsed.hasOperators) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                parsed.operatorSummary,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primaryColor,
                ),
              ),
            ),
          );
        }),

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
                  label: Text(_tagMode == 'AND' ? '關鍵字+標籤: 全部符合 (AND)' : '關鍵字+標籤: 任一符合 (OR)'),
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

  String? _resolvePageNumberDisplay(DocumentHit hit) {
    if (hit.pageNumber != null && hit.pageNumber! > 0) {
      return '${hit.pageNumber}';
    }
    final textToCheck = '${hit.highlight ?? ''} ${hit.document.summary}';
    final pageRegex = RegExp(r'(?:P\.?\s*([0-9]+(?:-[0-9]+)?)|第\s*([0-9]+(?:-[0-9]+)?)\s*頁)', caseSensitive: false);
    final match = pageRegex.firstMatch(textToCheck);
    if (match != null) {
      return match.group(1) ?? match.group(2);
    }
    if (hit.document.pageCount == 1) {
      return '1';
    }
    return null;
  }

  Widget _buildDocumentHitCard(DocumentHit hit) {
    final doc = hit.document;
    final scorePercent = (hit.score * 100).clamp(0, 100).toStringAsFixed(0);
    final dateFormat = DateFormat('yyyy-MM-dd');
    final pageDisplay = _resolvePageNumberDisplay(hit);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final targetPage = hit.pageNumber ?? (pageDisplay != null ? int.tryParse(pageDisplay) : null);
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (ctx) => DocumentDetailScreen(
                documentId: doc.id,
                repository: widget.repository,
                ollamaClient: widget.ollamaClient,
                initialPageNumber: targetPage,
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
              // Title, Badges & Score
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSourceBadge(doc.sourceType),
                  if (pageDisplay != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.teal.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.teal.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.bookmark_outline, size: 12, color: Colors.teal),
                          const SizedBox(width: 3),
                          Text(
                            '第 $pageDisplay 頁',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.teal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
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
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.secondaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),

              // Highlight snippet (原文全文命中片段與來源頁數)
              if (hit.highlight != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.format_quote, size: 15, color: Colors.amber),
                          const SizedBox(width: 5),
                          Text(
                            '原文命中引註',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.amber.shade900,
                            ),
                          ),
                          if (pageDisplay != null) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade200,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '第 $pageDisplay 頁',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.brown.shade800,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        hit.highlight!,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.4,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Literature Summary (增加顯示行數至 6 行，提供更多原始文獻摘要與頁數資訊)
              if (doc.summary.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey.shade900
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.notes_rounded, size: 14, color: Colors.blueGrey.shade700),
                          const SizedBox(width: 5),
                          Text(
                            '文獻摘要內容',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.blueGrey.shade700,
                            ),
                          ),
                          if (hit.highlight == null && pageDisplay != null) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.teal.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '來源：第 $pageDisplay 頁',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.teal,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        doc.summary,
                        maxLines: 6,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.45,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.grey.shade200
                              : Colors.grey.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Tags (支援顯示實質所屬頁數並可點擊直達該頁)
              if (doc.tags.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: doc.tags.take(6).map((tag) {
                    final isMatched = hit.matchedTags.contains(tag.name);
                    final tagPage = tag.pageNumber;
                    return InkWell(
                      borderRadius: BorderRadius.circular(4),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (ctx) => DocumentDetailScreen(
                              documentId: doc.id,
                              repository: widget.repository,
                              ollamaClient: widget.ollamaClient,
                              initialPageNumber: tagPage ?? hit.pageNumber,
                            ),
                          ),
                        );
                        _performSearch();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isMatched
                              ? AppTheme.accentColor.withValues(alpha: 0.2)
                              : AppTheme.getCategoryColor(tag.category).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                          border: isMatched ? Border.all(color: AppTheme.accentColor, width: 0.8) : null,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '#${tag.name}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: isMatched ? FontWeight.bold : FontWeight.normal,
                                color: isMatched ? Colors.amber.shade900 : AppTheme.getCategoryColor(tag.category),
                              ),
                            ),
                            if (tagPage != null && tagPage > 0) ...[
                              const SizedBox(width: 3),
                              Text(
                                '(P.$tagPage)',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                  color: isMatched
                                      ? Colors.amber.shade900
                                      : AppTheme.getCategoryColor(tag.category).withValues(alpha: 0.85),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],

              const SizedBox(height: 8),

              const SizedBox(height: 8),

              // Action Buttons: Related documents & Detail
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                    ),
                    icon: const Icon(Icons.hub_outlined, size: 13, color: Colors.amber),
                    label: const Text('🔗 關聯多文獻', style: TextStyle(fontSize: 11)),
                    onPressed: () => _showRelatedDocumentsDialog(doc),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                    ),
                    icon: const Icon(Icons.article_outlined, size: 14),
                    label: const Text('文獻詳情', style: TextStyle(fontSize: 11.5)),
                    onPressed: () async {
                      final targetPage = hit.pageNumber ?? (pageDisplay != null ? int.tryParse(pageDisplay) : null);
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (ctx) => DocumentDetailScreen(
                            documentId: doc.id,
                            repository: widget.repository,
                            ollamaClient: widget.ollamaClient,
                            initialPageNumber: targetPage,
                          ),
                        ),
                      );
                      _performSearch();
                    },
                  ),
                ],
              ),

              const SizedBox(height: 6),

              // Footer Meta
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      '${dateFormat.format(DateTime.fromMillisecondsSinceEpoch(doc.createdAt))} • 全文共 ${doc.pageCount} 頁 • ${doc.language}'
                      '${pageDisplay != null ? ' • 標示第 $pageDisplay 頁' : ''}',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                      overflow: TextOverflow.ellipsis,
                    ),
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

  Future<void> _showRelatedDocumentsDialog(Document doc) async {
    final allDocs = _allDocuments.isNotEmpty ? _allDocuments : await widget.repository.getAllDocuments();
    final related = _graphService.findRelatedDocuments(targetDoc: doc, allDocs: allDocs, limit: 6);

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.hub, color: Colors.amber, size: 26),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('跨文獻相關聯資訊 (llm-knowledge-graph)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                        Text('與《${doc.title}》高度關聯之文獻', style: const TextStyle(fontSize: 12, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (related.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('目前資料庫尚無其他與本文獻具高度關聯之文獻', style: TextStyle(color: Colors.grey))),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: related.length,
                    separatorBuilder: (context, index) => const Divider(height: 8),
                    itemBuilder: (ctx, idx) {
                      final r = related[idx];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.shade700,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('${r.scorePercent}%', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                        title: Text(r.document.title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold), maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 4,
                              runSpacing: 2,
                              children: [
                                ...r.sharedIcdCodes.map((icd) => Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(color: Colors.teal.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(3)),
                                  child: Text('共同 $icd', style: const TextStyle(fontSize: 9.5, color: Colors.teal, fontWeight: FontWeight.bold)),
                                )),
                                ...r.sharedEntities.take(3).map((e) => Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(3)),
                                  child: Text(e, style: const TextStyle(fontSize: 9.5, color: Colors.blue)),
                                )),
                              ],
                            ),
                          ],
                        ),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                        onTap: () {
                          Navigator.pop(ctx);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DocumentDetailScreen(
                                documentId: r.document.id,
                                repository: widget.repository,
                                ollamaClient: widget.ollamaClient,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('開啟本篇之知識圖譜視覺化'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => KnowledgeGraphScreen(
                          repository: widget.repository,
                          ollamaClient: widget.ollamaClient,
                          focusDocId: doc.id,
                          focusDocTitle: doc.title,
                        ),
                      ),
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

/// One row of the search syntax help dialog.
class _SyntaxRow extends StatelessWidget {
  final String operator;
  final String title;
  final String example;
  final String description;

  const _SyntaxRow({
    required this.operator,
    required this.title,
    required this.example,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              operator,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryColor,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 2),
                Text('範例：$example',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                const SizedBox(height: 2),
                Text(description, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
