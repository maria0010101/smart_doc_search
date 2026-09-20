import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_doc_search/data/datasources/koredb_datasource.dart';
import 'package:smart_doc_search/data/datasources/ollama_client.dart';
import 'package:smart_doc_search/data/datasources/sqlite_desktop_datasource.dart';
import 'package:smart_doc_search/data/models/document_model.dart';
import 'package:smart_doc_search/data/repositories/document_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('1. Disease Classification Option & Code System Tests', () {
    test('TagItem and TagDefinition support codeSystem field with JSON roundtrip', () {
      final tag = TagItem(
        id: 't-icd',
        name: '第2型糖尿病伴有高血糖 (E11.65)',
        category: '疾病分類編碼',
        codeSystem: 'ICD-10-CM',
        confidence: 0.95,
        source: 'ai',
      );

      final map = tag.toMap();
      expect(map['code_system'], 'ICD-10-CM');

      final jsonStr = tag.toJson();
      final deserialized = TagItem.fromJson(jsonStr);
      expect(deserialized.name, tag.name);
      expect(deserialized.codeSystem, 'ICD-10-CM');

      final def = TagDefinition(
        id: 'def-1',
        name: '心導管檢查',
        category: '處置編碼',
        codeSystem: 'ICD-10-PCS',
        usageCount: 5,
        createdAt: 1000,
        updatedAt: 1000,
      );

      final defMap = def.toMap();
      expect(defMap['code_system'], 'ICD-10-PCS');

      final deserializedDef = TagDefinition.fromJson(def.toJson());
      expect(deserializedDef.codeSystem, 'ICD-10-PCS');
    });

    test('OllamaClient toggles diseaseClassificationMode and selects appropriate prompt mode', () {
      final client = OllamaClient();
      expect(client.diseaseClassificationMode, isTrue);

      client.diseaseClassificationMode = false;
      expect(client.diseaseClassificationMode, isFalse);

      client.diseaseClassificationMode = true;
      expect(client.diseaseClassificationMode, isTrue);

      final promptClassification = client.buildAnalysisPrompt(
        '病歷記錄：患者診斷有急性心肌梗塞 I21.0',
        mode: 'medical_classification',
      );
      expect(promptClassification.contains('醫學與疾病分類深度分析專家'), isTrue);
      expect(promptClassification.contains('code_system'), isTrue);
      expect(promptClassification.contains('ICD-10-CM'), isTrue);

      final promptGeneral = client.buildAnalysisPrompt(
        '這是一份機器學習論文',
        mode: 'general',
      );
      expect(promptGeneral.contains('一般文獻辨識模式'), isTrue);
      expect(promptGeneral.contains('不須強調疾病分類相關內容的辨識'), isTrue);
    });
  });

  group('2. Bullet Summary & Page Citation Tests', () {
    test('AI prompt demands bullet-point structure and (P.X) page citations', () {
      final client = OllamaClient();
      final prompt = client.buildAnalysisPrompt('測試文獻全文內容');
      expect(prompt.contains('條列式'), isTrue);
      expect(prompt.contains('(P.1)'), isTrue);

      // Verify regex page parser
      const sampleBulletSummary = '''
- 本文探討第 2 型糖尿病之發病機制與高血糖危象處置。(P.1)
- 臨床試驗顯示 SGLT2 抑制劑可顯著降低心腎併發症風險。【第 5 頁】
- 建議合併二甲雙胍作為一線治療標準指引。(P. 12)
''';
      final pageRegex = RegExp(r'(\(|【)(P\.?\s*([0-9]+)|第\s*([0-9]+)\s*頁)(\)|】)', caseSensitive: false);
      final lines = sampleBulletSummary.split('\n').where((l) => l.trim().isNotEmpty).toList();

      final parsedPages = <int>[];
      for (final line in lines) {
        final matches = pageRegex.allMatches(line);
        if (matches.isNotEmpty) {
          final m = matches.first;
          final pageStr = m.group(3) ?? m.group(4);
          if (pageStr != null) {
            parsedPages.add(int.parse(pageStr));
          }
        }
      }

      expect(parsedPages, [1, 5, 12]);
    });
  });

  group('3. KoreDB Backup, GZIP Compression & Snapshot Rollback Tests', () {
    late KoreDbDataSource dataSource;
    late DocumentRepository repository;

    setUp(() async {
      dataSource = KoreDbNativeDataSource();
      repository = DocumentRepository(dataSource: dataSource);

      await repository.saveDocument(Document(
        id: 'backup-doc-1',
        title: '臨床指引文件',
        sourceType: 'pdf',
        filePath: '/docs/doc1.pdf',
        fileHash: 'hash-abc',
        createdAt: 1000,
        updatedAt: 1000,
        pageCount: 3,
        tags: [
          TagItem(id: 't-1', name: '高血壓', category: '疾病/症狀', codeSystem: 'ICD-10-CM'),
        ],
        summary: '- 條列式高血壓指引 (P.1)',
      ));
    });

    test('exportCompressedBackup generates valid GZIP bytes and can be decoded', () async {
      final gzBytes = await repository.exportCompressedBackup();
      expect(gzBytes.isNotEmpty, isTrue);

      // Verify GZIP magic number 0x1f, 0x8b
      expect(gzBytes[0], 0x1f);
      expect(gzBytes[1], 0x8b);

      final uncompressed = utf8.decode(gzip.decode(gzBytes));
      final map = jsonDecode(uncompressed) as Map<String, dynamic>;
      expect(map['version'], '2.0');
      expect(map['documents'], isNotEmpty);
      expect((map['documents'] as List).first['title'], '臨床指引文件');
    });

    test('restoreBackupWithValidation succeeds with valid v2.0 JSON and GZIP', () async {
      final gzBytes = await repository.exportCompressedBackup();

      // Clear existing docs
      await dataSource.clearAll();
      expect(await repository.getAllDocuments(), isEmpty);

      // Restore from GZIP
      final result = await repository.restoreBackupWithValidation(gzBytes);
      expect(result.success, isTrue);
      expect(result.message.contains('成功還原備份'), isTrue);

      final restoredDocs = await repository.getAllDocuments();
      expect(restoredDocs.length, 1);
      expect(restoredDocs.first.title, '臨床指引文件');
      expect(restoredDocs.first.tags.first.codeSystem, 'ICD-10-CM');
    });

    test('restoreBackupWithValidation handles v1.0 migration automatically', () async {
      final v1Backup = {
        'version': '1.0',
        'exportTime': DateTime.now().millisecondsSinceEpoch,
        'documents': [
          {
            'id': 'v1-doc',
            'title': '舊版文獻',
            'sourceType': 'pdf',
            'filePath': '/docs/old.pdf',
            'fileHash': 'hash-old',
            'createdAt': 1000,
            'updatedAt': 1000,
            'pageCount': 1,
            'tags': [
              {'id': 't-old', 'name': 'ICD-10 E11 糖尿病', 'category': '疾病分類編碼'}
            ],
            'summary': '舊版摘要',
          }
        ],
        'pages': [],
        'tags': [],
      };

      final rawBytes = utf8.encode(jsonEncode(v1Backup));
      final res = await repository.restoreBackupWithValidation(rawBytes);
      expect(res.success, isTrue);
      expect(res.migratedVersion, '1.0');

      final docs = await repository.getAllDocuments();
      final v1Doc = docs.firstWhere((d) => d.id == 'v1-doc');
      expect(v1Doc.tags.first.codeSystem, 'ICD-10-CM');
    });

    test('restoreBackupWithValidation rolls back to snapshot if restore data is corrupt', () async {
      final initialDocs = await repository.getAllDocuments();
      expect(initialDocs.length, 1);

      // Malformed json bytes
      final corruptBytes = utf8.encode('{"version": "2.0", "documents": [corrupt-json]}');
      final res = await repository.restoreBackupWithValidation(corruptBytes);
      expect(res.success, isFalse);
      expect(res.message, isNotEmpty);

      // Documents must be preserved via snapshot rollback
      final docsAfterRollback = await repository.getAllDocuments();
      expect(docsAfterRollback.length, 1);
      expect(docsAfterRollback.first.id, 'backup-doc-1');
    });

    test('exportBackupToFile formats filename with koredb_backup_ and yyyyMMdd date info', () async {
      final tempDir = await Directory.systemTemp.createTemp('koredb_test_');
      final testTime = DateTime(2026, 9, 20, 15, 30, 45);
      final gzPath = await repository.exportBackupToFile(compress: true, timestamp: testTime, targetDirectory: tempDir);
      final jsonPath = await repository.exportBackupToFile(compress: false, timestamp: testTime, targetDirectory: tempDir);

      expect(gzPath.contains('koredb_backup_20260920_153045.json.gz'), isTrue);
      expect(jsonPath.contains('koredb_backup_20260920_153045.json'), isTrue);

      final gzFile = File(gzPath);
      final jsonFile = File(jsonPath);
      expect(await gzFile.exists(), isTrue);
      expect(await jsonFile.exists(), isTrue);

      // Verify file content is valid
      final gzBytes = await gzFile.readAsBytes();
      expect(gzBytes[0], 0x1f);
      expect(gzBytes[1], 0x8b);

      final jsonContent = await jsonFile.readAsString();
      final map = jsonDecode(jsonContent) as Map<String, dynamic>;
      expect(map['version'], '2.0');
      expect(map['documents'], isNotEmpty);

      // Clean up test files and temp dir
      await tempDir.delete(recursive: true);
    });
  });

  group('4. SQLite Desktop DataSource & Cross-Platform Schema Interchange Tests', () {
    late SqliteDesktopDataSource desktopSource;

    setUp(() async {
      desktopSource = SqliteDesktopDataSource(customDbPath: inMemoryDatabasePath);
    });

    tearDown(() async {
      await desktopSource.close();
    });

    test('SqliteDesktopDataSource inserts, queries, updates and exports matching JSON schema', () async {
      final doc = Document(
        id: 'desktop-doc-1',
        title: 'Windows 11 與 Linux 跨端互通文獻',
        sourceType: 'pdf',
        filePath: 'C:\\docs\\win.pdf',
        fileHash: 'win-hash-123',
        createdAt: 2000,
        updatedAt: 2000,
        pageCount: 5,
        tags: [
          TagItem(id: 't-win', name: 'ICD-10-PCS 心導管介入術', category: '疾病分類編碼', codeSystem: 'ICD-10-PCS'),
        ],
        summary: '- 桌面端資料庫互通測試 (P.1)',
      );

      final insertedId = await desktopSource.insertDocument(doc);
      expect(insertedId, 'desktop-doc-1');

      final fetched = await desktopSource.getDocument('desktop-doc-1');
      expect(fetched, isNotNull);
      expect(fetched!.title, doc.title);
      expect(fetched.tags.first.codeSystem, 'ICD-10-PCS');

      // Export JSON from desktop source
      final exportedJson = await desktopSource.exportBackup();
      final map = jsonDecode(exportedJson) as Map<String, dynamic>;
      expect(map['version'], '2.0');
      expect((map['documents'] as List).length, 1);

      // Restore same JSON into mobile KoreDbNativeDataSource to verify cross-platform interchange
      final mobileSource = KoreDbNativeDataSource();
      await mobileSource.clearAll();
      final restoreOk = await mobileSource.restoreBackup(exportedJson);
      expect(restoreOk, isTrue);

      final mobileDocs = await mobileSource.getAllDocuments();
      expect(mobileDocs.length, 1);
      expect(mobileDocs.first.title, 'Windows 11 與 Linux 跨端互通文獻');
      expect(mobileDocs.first.tags.first.codeSystem, 'ICD-10-PCS');
    });

    test('SqliteDesktopDataSource handles backup with duplicate tags without UNIQUE constraint failure', () async {
      // Simulate the exact failure from Windows 11 screenshot error.jpg:
      // Multiple tag items with the exact same name 'coccygeal joint fusion' but different IDs
      final payloadWithDuplicateTags = json.encode({
        'version': '2.0',
        'timestamp': 1789840539675,
        'documents': [
          {
            'id': 'doc-1',
            'title': '關節融合文獻 1',
            'sourceType': 'pdf',
            'filePath': 'C:\\docs\\doc1.pdf',
            'fileHash': 'hash1',
            'createdAt': 1000,
            'updatedAt': 1000,
            'pageCount': 2,
            'tags': [
              {
                'id': 'med_t_1789840539675658_181',
                'name': 'coccygeal joint fusion',
                'category': '醫學術語',
                'code_system': 'ICD-10-PCS',
              }
            ],
            'summary': '- 關節指引 (P.1)',
            'metadata': {},
          },
          {
            'id': 'doc-2',
            'title': '關節融合文獻 2',
            'sourceType': 'pdf',
            'filePath': 'C:\\docs\\doc2.pdf',
            'fileHash': 'hash2',
            'createdAt': 2000,
            'updatedAt': 2000,
            'pageCount': 2,
            'tags': [
              {
                'id': 'med_t_1789840539675659_999',
                'name': 'coccygeal joint fusion',
                'category': '醫學術語',
                'code_system': 'ICD-10-PCS',
              }
            ],
            'summary': '- 關節指引 2 (P.1)',
            'metadata': {},
          }
        ],
        'pages': [],
        'tags': [
          {
            'id': 'med_t_1789840539675658_181',
            'name': 'coccygeal joint fusion',
            'category': '醫學術語',
            'aliases': [],
            'usage_count': 1,
            'code_system': null,
            'created_at': 0,
            'updated_at': 0,
          },
          {
            'id': 'med_t_1789840539675659_999',
            'name': 'coccygeal joint fusion',
            'category': '醫學術語',
            'aliases': ['coccyx fusion'],
            'usage_count': 1,
            'code_system': 'ICD-10-PCS',
            'created_at': 0,
            'updated_at': 100,
          }
        ],
      });

      // 1. Direct restore into desktop SQLite datasource must succeed without throwing SQLite 2067 UNIQUE constraint failed
      final ok = await desktopSource.restoreBackup(payloadWithDuplicateTags);
      expect(ok, isTrue);

      final tags = await desktopSource.getAllTags();
      expect(tags.length, 1);
      expect(tags.first.name, 'coccygeal joint fusion');
      expect(tags.first.usageCount, 2);
      expect(tags.first.codeSystem, 'ICD-10-PCS');
      expect(tags.first.aliases.contains('coccyx fusion'), isTrue);

      final docs = await desktopSource.getAllDocuments();
      expect(docs.length, 2);

      // 2. Also verify DocumentRepository.restoreBackupWithValidation succeeds
      final repo = DocumentRepository(dataSource: desktopSource);
      final res = await repo.restoreBackupWithValidation(payloadWithDuplicateTags);
      expect(res.success, isTrue);
      expect(res.message.contains('成功還原備份'), isTrue);
    });

    test('SqliteDesktopDataSource successfully imports real user backup file with 105 duplicate tags', () async {
      final userBackupFile = File('/tmp/user_backup.json');
      if (!await userBackupFile.exists()) return;

      final content = await userBackupFile.readAsString();
      final repo = DocumentRepository(dataSource: desktopSource);
      final res = await repo.restoreBackupWithValidation(content);
      expect(res.success, isTrue);

      final stats = await desktopSource.getStats();
      expect(stats['documentCount'], 5);
      expect(stats['pageCount'], 176);
      expect(stats['tagCount'], 982); // 982 unique tags case-insensitively deduplicated from 1159
    });
  });

  group('5. Cross-Platform Literature Folder Path & Fallback Tests', () {
    test('SqliteDesktopDataSource copies literature to Smart_Doc directory', () async {
      final tempDocDir = await Directory.systemTemp.createTemp('smart_doc_docs_');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (MethodCall methodCall) async {
          if (methodCall.method == 'getApplicationDocumentsDirectory') {
            return tempDocDir.path;
          }
          return null;
        },
      );

      final desktopSource = SqliteDesktopDataSource(customDbPath: inMemoryDatabasePath);
      final tempSourceDir = await Directory.systemTemp.createTemp('smart_doc_src_');
      final testFile = File('${tempSourceDir.path}/test_literature.pdf');
      await testFile.writeAsString('Dummy PDF content for Smart_Doc test');

      final copiedPath = await desktopSource.copyToDocuments(testFile.path, 'test_literature.pdf');
      expect(copiedPath, isNotNull);
      expect(copiedPath, contains('Smart_Doc'));
      expect(copiedPath, endsWith('test_literature.pdf'));

      final copiedFile = File(copiedPath!);
      expect(await copiedFile.exists(), isTrue);
      expect(await copiedFile.readAsString(), 'Dummy PDF content for Smart_Doc test');

      // Cleanup
      await testFile.delete();
      await tempSourceDir.delete(recursive: true);
      await tempDocDir.delete(recursive: true);
      await desktopSource.close();
    });

    test('SqliteDesktopDataSource openFile returns false when file does not exist anywhere', () async {
      final desktopSource = SqliteDesktopDataSource(customDbPath: inMemoryDatabasePath);
      final res = await desktopSource.openFile('/non/existent/path/never_existed.pdf');
      expect(res, isFalse);
      await desktopSource.close();
    });
  });

  group('6. Reactive Data Change Notification Stream Tests', () {
    test('saveDocument, updateDocument, and deleteDocument trigger onDataChanged', () async {
      final desktopSource = SqliteDesktopDataSource(customDbPath: inMemoryDatabasePath);
      final repo = DocumentRepository(dataSource: desktopSource);

      int changeEvents = 0;
      final sub = repo.onDataChanged.listen((_) => changeEvents++);

      final doc = Document(
        id: 'doc-reactive-1',
        title: 'Reactive Test Doc',
        filePath: '/test/reactive.pdf',
        sourceType: 'pdf',
        fileHash: 'hash-reactive-1',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        pageCount: 1,
        language: 'zh-TW',
        tags: [TagItem(id: 't1', name: '測試標籤', category: '主題')],
      );

      // Save
      await repo.saveDocument(doc);
      await Future.delayed(const Duration(milliseconds: 150));
      expect(changeEvents, 1);

      // Update
      final updated = doc.copyWith(title: 'Updated Title');
      await repo.updateDocument(updated);
      await Future.delayed(const Duration(milliseconds: 150));
      expect(changeEvents, 2);

      // Delete
      await repo.deleteDocument(doc.id);
      await Future.delayed(const Duration(milliseconds: 150));
      expect(changeEvents, 3);

      await sub.cancel();
      repo.dispose();
      await desktopSource.close();
    });

    test('updateTag, deleteTag, and mergeTags trigger onDataChanged', () async {
      final desktopSource = SqliteDesktopDataSource(customDbPath: inMemoryDatabasePath);
      final repo = DocumentRepository(dataSource: desktopSource);

      final tag = TagDefinition(
        id: 'tag-react-1',
        name: '反應式測試標籤',
        category: '主題',
        usageCount: 1,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );

      // Seed tag
      await repo.restoreBackupWithValidation(json.encode({
        'version': '2.0',
        'documents': [],
        'pages': [],
        'tags': [tag.toMap()],
      }));

      int changeEvents = 0;
      final sub = repo.onDataChanged.listen((_) => changeEvents++);

      // Update existing tag
      final updatedTag = tag.copyWith(name: '反應式更新標籤');
      final updateOk = await repo.updateTag(updatedTag);
      expect(updateOk, isTrue);
      await Future.delayed(const Duration(milliseconds: 150));
      expect(changeEvents, 1);

      // Delete existing tag
      final deleteOk = await repo.deleteTag(tag.id);
      expect(deleteOk, isTrue);
      await Future.delayed(const Duration(milliseconds: 150));
      expect(changeEvents, 2);

      await sub.cancel();
      repo.dispose();
      await desktopSource.close();
    });

    test('restoreBackup and clearAll trigger immediate onDataChanged', () async {
      final desktopSource = SqliteDesktopDataSource(customDbPath: inMemoryDatabasePath);
      final repo = DocumentRepository(dataSource: desktopSource);

      int changeEvents = 0;
      final sub = repo.onDataChanged.listen((_) => changeEvents++);

      final backupJson = json.encode({
        'version': '2.0',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'documents': [],
        'pages': [],
        'tags': [],
      });

      await repo.restoreBackupWithValidation(backupJson);
      // immediate: true doesn't need 100ms debounce
      await Future.delayed(const Duration(milliseconds: 10));
      expect(changeEvents, 1);

      await repo.clearAll();
      await Future.delayed(const Duration(milliseconds: 10));
      expect(changeEvents, 2);

      await sub.cancel();
      repo.dispose();
      await desktopSource.close();
    });
  });
}
