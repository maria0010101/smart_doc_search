import 'package:smart_doc_search/data/datasources/koredb_datasource.dart';
import 'package:smart_doc_search/data/datasources/ollama_client.dart';
import 'package:smart_doc_search/data/models/document_model.dart';
import 'package:smart_doc_search/features/search/search_query_parser.dart';

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
    int limit = 60,
    int offset = 0,
  }) async {
    // 1. Parse operator-annotated query into required (+), optional and
    //    excluded (-) keyword groups. Plain space separated keywords remain
    //    optional and only influence ranking, matching search engine behaviour.
    final parsed = SearchQueryParser.parse(queryText);
    final hasFilters = selectedTags.isNotEmpty ||
        fileTypeFilters.isNotEmpty ||
        startDate != null ||
        endDate != null;

    // 2. If semantic search is requested, generate a query embedding from the
    //    positive keywords only (operators carry no semantic meaning).
    final semanticQueryText = parsed.positiveKeywords.join(' ');
    List<double>? queryEmbedding;
    if (enableSemanticSearch && semanticQueryText.trim().isNotEmpty) {
      try {
        final emb = await ollamaClient.embed(text: semanticQueryText);
        if (emb.isNotEmpty) queryEmbedding = emb;
      } catch (_) {
        // Fallback to purely keyword + tag search
      }
    }

    // 3. Call the storage engine hybrid search. A wide candidate window is
    //    fetched so that filters/sorting still see the full matching set.
    // Only the window that can actually be displayed is requested, so the
    // storage engine never computes snippets/pages for rows the UI drops.
    final needsWideWindow =
        hasFilters || sortOrder != SearchSortOrder.relevance;
    final rawResult = await dataSource.hybridSearch(
      keywords: parsed.toEncodedKeywords(),
      tags: selectedTags,
      tagMode: tagMode,
      semanticEmbedding: queryEmbedding,
      limit: needsWideWindow ? 500 : (offset + limit),
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
