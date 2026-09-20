import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:smart_doc_search/core/constants/app_constants.dart';
import 'package:smart_doc_search/data/datasources/koredb_datasource.dart';
import 'package:smart_doc_search/data/models/document_model.dart';

class RestoreResult {
  final bool success;
  final String message;
  final String? migratedVersion;

  RestoreResult({
    required this.success,
    required this.message,
    this.migratedVersion,
  });
}

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
    return docs.any((d) => d.fileHash == hash);
  }

  Future<List<PageItem>> getDocumentPages(String documentId) async {
    return dataSource.getPages(documentId);
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

  Future<bool> mergeTags(String sourceTagId, String targetTagId) async {
    final tags = await dataSource.getAllTags();
    final sourceMatches = tags.where((t) => t.id == sourceTagId || t.name == sourceTagId);
    if (sourceMatches.isEmpty) return false;
    final sourceTag = sourceMatches.first;

    final targetMatches = tags.where((t) => t.id == targetTagId || t.name == targetTagId);
    final TagDefinition targetTag;
    if (targetMatches.isNotEmpty) {
      targetTag = targetMatches.first;
    } else {
      // If target tag doesn't exist, create it based on source category
      targetTag = TagDefinition(
        id: targetTagId,
        name: targetTagId,
        category: sourceTag.category,
        codeSystem: sourceTag.codeSystem,
        usageCount: 0,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
    }

    // Merge aliases into target
    final combinedAliases = {...targetTag.aliases, sourceTag.name, ...sourceTag.aliases}.toList();
    final updatedTarget = targetTag.copyWith(
      aliases: combinedAliases,
      usageCount: targetTag.usageCount + sourceTag.usageCount,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await dataSource.updateTag(updatedTarget);

    // Update references in all documents
    final docs = await dataSource.getAllDocuments();
    for (final doc in docs) {
      bool changed = false;
      final updatedTags = doc.tags.map((t) {
        if (t.name == sourceTag.name) {
          changed = true;
          return t.copyWith(
            name: targetTag.name,
            category: targetTag.category,
            codeSystem: targetTag.codeSystem ?? t.codeSystem,
          );
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

  /// Exports all Document, Page, Tag data as a GZIP-compressed JSON byte array (.json.gz)
  Future<List<int>> exportCompressedBackup() async {
    final jsonStr = await dataSource.exportBackup();
    final bytes = utf8.encode(jsonStr);
    return gzip.encode(bytes);
  }

  /// Exports backup to a file in device Downloads folder (on Android / Desktop), returns saved file path.
  /// The filename includes export date and time (Year, Month, Day, Hour, Minute, Second):
  /// e.g. koredb_backup_YYYYMMDD_HHmmss.json.gz or koredb_backup_YYYYMMDD_HHmmss.json
  Future<String> exportBackupToFile({
    bool compress = true,
    DateTime? timestamp,
    Directory? targetDirectory,
  }) async {
    final now = timestamp ?? DateTime.now();
    final dateStr = DateFormat('yyyyMMdd_HHmmss').format(now);
    final fileName = compress
        ? 'koredb_backup_$dateStr.json.gz'
        : 'koredb_backup_$dateStr.json';

    // If caller explicitly specified a directory, use it directly
    if (targetDirectory != null) {
      if (!await targetDirectory.exists()) {
        await targetDirectory.create(recursive: true);
      }
      final file = File('${targetDirectory.path}/$fileName');
      if (compress) {
        final gzBytes = await exportCompressedBackup();
        await file.writeAsBytes(gzBytes);
      } else {
        final jsonStr = await dataSource.exportBackup();
        await file.writeAsString(jsonStr);
      }
      return file.path;
    }

    // On Android: export directly to device public Download folder via MediaStore
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final bytes = compress
            ? await exportCompressedBackup()
            : utf8.encode(await dataSource.exportBackup());
        const channel = MethodChannel(AppConstants.nativeToolsChannel);
        final path = await channel.invokeMethod<String>('exportBackupToDownloads', {
          'fileName': fileName,
          'bytes': Uint8List.fromList(bytes),
        });
        if (path != null && path.isNotEmpty) {
          return path;
        }
      } catch (e) {
        debugPrint('exportBackupToDownloads Android native error: $e');
      }
    }

    // Desktop (Windows, Linux, macOS) or fallback
    Directory? downloadDir;
    try {
      if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        downloadDir = await getDownloadsDirectory();
      }
    } catch (_) {}
    downloadDir ??= await getApplicationDocumentsDirectory();

    final backupDir = Directory(downloadDir.path);
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }

    final file = File('${backupDir.path}/$fileName');
    if (compress) {
      final gzBytes = await exportCompressedBackup();
      await file.writeAsBytes(gzBytes);
      return file.path;
    } else {
      final jsonStr = await dataSource.exportBackup();
      await file.writeAsString(jsonStr);
      return file.path;
    }
  }

  Future<bool> restoreBackup(String backupJson) async {
    return dataSource.restoreBackup(backupJson);
  }

  /// Restores backup from raw bytes or string with:
  /// 1. Automatic GZIP decompression (detects 0x1f, 0x8b magic header)
  /// 2. Schema validation and version migration (v1.0 -> v2.0)
  /// 3. Transaction protection with automatic snapshot rollback if import fails
  Future<RestoreResult> restoreBackupWithValidation(dynamic inputData) async {
    String jsonStr = '';
    try {
      if (inputData is List<int>) {
        if (inputData.length >= 2 && inputData[0] == 0x1f && inputData[1] == 0x8b) {
          // Gzipped
          final decompressed = gzip.decode(inputData);
          jsonStr = utf8.decode(decompressed);
        } else {
          jsonStr = utf8.decode(inputData);
        }
      } else if (inputData is String) {
        jsonStr = inputData;
      } else {
        return RestoreResult(success: false, message: '不支援的備份資料格式');
      }
    } catch (e) {
      return RestoreResult(success: false, message: '解壓縮或解碼備份失敗: $e');
    }

    // 1. JSON parse & Schema Validation
    Map<String, dynamic> root;
    try {
      final decoded = json.decode(jsonStr);
      if (decoded is! Map) {
        return RestoreResult(success: false, message: '備份檔案非有效 JSON 物件');
      }
      root = Map<String, dynamic>.from(decoded);
    } catch (e) {
      return RestoreResult(success: false, message: 'JSON 解析失敗: $e');
    }

    // 2. Schema Version & Migration
    final version = (root['version'] ?? '1.0').toString();
    if (!root.containsKey('documents') && !root.containsKey('pages') && !root.containsKey('tags')) {
      return RestoreResult(success: false, message: '無效的備份結構：缺少 documents/pages/tags 區塊');
    }

    final rawDocs = (root['documents'] as List?) ?? [];
    final rawPages = (root['pages'] as List?) ?? [];
    final rawTags = (root['tags'] as List?) ?? [];

    // Migrate v1.0 -> v2.0 if needed
    final migratedDocs = <Map<String, dynamic>>[];
    for (final d in rawDocs) {
      if (d is Map) {
        final dMap = Map<String, dynamic>.from(d);
        if (dMap['sourceType'] == null && dMap['source_type'] == null) {
          dMap['sourceType'] = 'pdf';
        }
        if (dMap['tags'] is List) {
          final mTags = (dMap['tags'] as List).map((t) {
            if (t is Map) {
              final tMap = Map<String, dynamic>.from(t);
              if (tMap['category'] == '疾病分類編碼' && tMap['code_system'] == null && tMap['codeSystem'] == null) {
                tMap['code_system'] = 'ICD-10-CM';
              }
              return tMap;
            }
            return t;
          }).toList();
          dMap['tags'] = mTags;
        }
        migratedDocs.add(dMap);
      }
    }

    final Map<String, Map<String, dynamic>> deduplicatedTagsMap = {};
    for (final t in rawTags) {
      if (t is Map) {
        final tMap = Map<String, dynamic>.from(t);
        if (tMap['category'] == '疾病分類編碼' && tMap['code_system'] == null && tMap['codeSystem'] == null) {
          tMap['code_system'] = 'ICD-10-CM';
        }
        final name = (tMap['name'] ?? '').toString().trim();
        final key = name.toLowerCase();
        if (key.isEmpty) continue;

        if (!deduplicatedTagsMap.containsKey(key)) {
          deduplicatedTagsMap[key] = tMap;
        } else {
          final existing = deduplicatedTagsMap[key]!;
          final c1 = (existing['usageCount'] ?? existing['usage_count'] ?? 0) as num;
          final c2 = (tMap['usageCount'] ?? tMap['usage_count'] ?? 0) as num;
          existing['usageCount'] = c1.toInt() + c2.toInt();
          existing['usage_count'] = existing['usageCount'];
          if ((existing['code_system'] == null || existing['code_system'] == '') &&
              (tMap['code_system'] != null && tMap['code_system'] != '')) {
            existing['code_system'] = tMap['code_system'];
          }
        }
      }
    }
    final migratedTags = deduplicatedTagsMap.values.toList();

    final migratedPayload = json.encode({
      'version': '2.0',
      'migratedFrom': version,
      'timestamp': root['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
      'documents': migratedDocs,
      'pages': rawPages,
      'tags': migratedTags,
    });

    // 3. Transaction Protection (Snapshot Rollback)
    String? currentSnapshot;
    try {
      currentSnapshot = await dataSource.exportBackup();
    } catch (e) {
      debugPrint('Warning: unable to take pre-restore snapshot: $e');
    }

    try {
      final ok = await dataSource.restoreBackup(migratedPayload);
      if (!ok) {
        if (currentSnapshot != null) {
          await dataSource.restoreBackup(currentSnapshot);
        }
        return RestoreResult(success: false, message: '資料庫寫入失敗，已執行回滾還原');
      }

      final stats = await dataSource.getStats();
      return RestoreResult(
        success: true,
        message: '成功還原備份！已匯入 ${stats['documentCount']} 份文獻、${stats['pageCount']} 頁面、${stats['tagCount']} 個標籤 (Schema v$version -> v2.0)',
        migratedVersion: version != '2.0' ? version : null,
      );
    } catch (e) {
      if (currentSnapshot != null) {
        try {
          await dataSource.restoreBackup(currentSnapshot);
        } catch (_) {}
      }
      return RestoreResult(success: false, message: '匯入中途發生例外: $e，已復原原資料庫狀態');
    }
  }

  Future<bool> clearAll() async {
    return dataSource.clearAll();
  }

  Future<bool> openFile(String filePath) async {
    return dataSource.openFile(filePath);
  }

  Future<String?> copyToDocuments(String sourcePath, String fileName) async {
    return dataSource.copyToDocuments(sourcePath, fileName);
  }
}
