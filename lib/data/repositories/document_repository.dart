import 'package:smart_doc_search/data/datasources/koredb_datasource.dart';
import 'package:smart_doc_search/data/models/document_model.dart';

class DocumentRepository {
  final KoreDbDataSource dataSource;

  DocumentRepository({required this.dataSource});

  Future<String> saveDocument(Document doc) async {
    return dataSource.insertDocument(doc);
  }

  Future<bool> updateDocument(Document doc) async {
    return dataSource.updateDocument(doc);
  }

  Future<bool> deleteDocument(String id) async {
    return dataSource.deleteDocument(id);
  }

  Future<Document?> getDocument(String id) async {
    return dataSource.getDocument(id);
  }

  Future<List<Document>> getAllDocuments() async {
    return dataSource.getAllDocuments();
  }

  Future<bool> checkHashExists(String hash) async {
    final docs = await dataSource.getAllDocuments();
    return docs.any((d) => d.fileHash.isNotEmpty && d.fileHash.toLowerCase() == hash.toLowerCase());
  }

  Future<List<PageItem>> getDocumentPages(String docId) async {
    return dataSource.getPages(docId);
  }

  Future<String> savePage(PageItem page) async {
    return dataSource.insertPage(page);
  }

  Future<List<TagDefinition>> getAllTags() async {
    return dataSource.getAllTags();
  }

  Future<bool> updateTag(TagDefinition tag) async {
    return dataSource.updateTag(tag);
  }

  Future<bool> deleteTag(String tagId) async {
    return dataSource.deleteTag(tagId);
  }

  Future<bool> mergeTags(String sourceTagId, String targetTagName) async {
    final tags = await dataSource.getAllTags();
    final sourceTag = tags.firstWhere((t) => t.id == sourceTagId, orElse: () => TagDefinition(id: '', name: '', createdAt: 0, updatedAt: 0));
    if (sourceTag.id.isEmpty) return false;

    // Update documents containing source tag to target tag name
    final docs = await dataSource.getAllDocuments();
    for (final doc in docs) {
      bool changed = false;
      final updatedTags = doc.tags.map((t) {
        if (t.name.trim().toLowerCase() == sourceTag.name.trim().toLowerCase()) {
          changed = true;
          return t.copyWith(name: targetTagName);
        }
        return t;
      }).toList();

      if (changed) {
        await dataSource.updateDocument(doc.copyWith(tags: updatedTags));
      }
    }

    // Delete source tag definition
    await dataSource.deleteTag(sourceTagId);
    return true;
  }

  Future<SearchResult> search(SearchQuery query) async {
    return dataSource.hybridSearch(
      keywords: query.keywords,
      tags: query.tags,
      tagMode: query.tagMode,
      limit: query.limit,
      offset: query.offset,
    );
  }

  Future<Map<String, dynamic>> getStorageStats() async {
    return dataSource.getStats();
  }

  Future<String> exportBackup() async {
    return dataSource.exportBackup();
  }

  Future<bool> restoreBackup(String backupJson) async {
    return dataSource.restoreBackup(backupJson);
  }

  Future<bool> clearAll() async {
    return dataSource.clearAll();
  }
}
