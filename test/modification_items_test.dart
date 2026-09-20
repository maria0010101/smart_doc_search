import 'dart:convert';
import 'dart:io';
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
  });
}
