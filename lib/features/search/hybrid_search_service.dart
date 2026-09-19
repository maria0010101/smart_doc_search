import 'package:smart_doc_search/data/datasources/koredb_datasource.dart';
import 'package:smart_doc_search/data/datasources/ollama_client.dart';
import 'package:smart_doc_search/data/models/document_model.dart';

enum SearchSortOrder {
  relevance,
  newestImport,
  newestModified,
  title,
}

class HybridSearchService {
  final KoreDbDataSource dataSource;
  final OllamaClient ollamaClient;

  HybridSearchService({
    required this.dataSource,
    required this.ollamaClient,
  });

  Future<SearchResult> executeSearch({
    required String queryText,
    List<String> selectedTags = const [],
    String tagMode = 'AND',
    bool enableSemanticSearch = true,
    List<String> fileTypeFilters = const [],
    DateTime? startDate,
    DateTime? endDate,
    SearchSortOrder sortOrder = SearchSortOrder.relevance,
    int limit = 20,
    int offset = 0,
  }) async {
    // 1. Tokenize queryText into keywords
    final keywords = queryText.split(RegExp(r'\s+')).where((s) => s.trim().isNotEmpty).toList();

    // 2. If semantic search is requested, generate query embedding
    List<double>? queryEmbedding;
    if (enableSemanticSearch && queryText.trim().isNotEmpty) {
      try {
        final emb = await ollamaClient.embed(text: queryText);
        if (emb.isNotEmpty) queryEmbedding = emb;
      } catch (_) {
        // Fallback to purely keyword + tag search
      }
    }

    // 3. Call KoreDB hybrid search
    final rawResult = await dataSource.hybridSearch(
      keywords: keywords,
      tags: selectedTags,
      tagMode: tagMode,
      semanticEmbedding: queryEmbedding,
      limit: 100, // Fetch broader set for filtering
      offset: 0,
    );

    // 4. Apply Filters
    var filteredItems = rawResult.items.where((hit) {
      final doc = hit.document;

      // File type filter
      if (fileTypeFilters.isNotEmpty && !fileTypeFilters.contains(doc.sourceType.toLowerCase())) {
        return false;
      }

      // Date range filter
      if (startDate != null && doc.createdAt < startDate.millisecondsSinceEpoch) {
        return false;
      }
      if (endDate != null && doc.createdAt > endDate.millisecondsSinceEpoch) {
        return false;
      }

      return true;
    }).toList();

    // 5. Apply Sorting
    switch (sortOrder) {
      case SearchSortOrder.relevance:
        filteredItems.sort((a, b) => b.score.compareTo(a.score));
        break;
      case SearchSortOrder.newestImport:
        filteredItems.sort((a, b) => b.document.createdAt.compareTo(a.document.createdAt));
        break;
      case SearchSortOrder.newestModified:
        filteredItems.sort((a, b) => b.document.updatedAt.compareTo(a.document.updatedAt));
        break;
      case SearchSortOrder.title:
        filteredItems.sort((a, b) => a.document.title.compareTo(b.document.title));
        break;
    }

    // 6. Pagination
    final total = filteredItems.length;
    final pagedItems = filteredItems.skip(offset).take(limit).toList();

    return SearchResult(
      items: pagedItems,
      total: total,
      tookMs: rawResult.tookMs,
    );
  }
}
