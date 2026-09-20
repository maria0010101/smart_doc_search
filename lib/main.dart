import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_doc_search/core/constants/app_constants.dart';
import 'package:smart_doc_search/core/theme/app_theme.dart';
import 'package:smart_doc_search/data/datasources/koredb_datasource.dart';
import 'package:smart_doc_search/data/datasources/ollama_client.dart';
import 'package:smart_doc_search/data/datasources/sqlite_desktop_datasource.dart';
import 'package:smart_doc_search/data/models/document_model.dart';
import 'package:smart_doc_search/data/repositories/document_repository.dart';
import 'package:smart_doc_search/features/home/home_screen.dart';
import 'package:smart_doc_search/features/import/import_screen.dart';
import 'package:smart_doc_search/features/import/import_service.dart';
import 'package:smart_doc_search/features/search/hybrid_search_service.dart';
import 'package:smart_doc_search/features/search/search_screen.dart';
import 'package:smart_doc_search/features/settings/settings_screen.dart';
import 'package:smart_doc_search/features/tags/tag_management_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final isDarkMode = prefs.getBool(AppConstants.prefDarkMode) ?? false;

  final savedProvId = prefs.getString(AppConstants.prefAiProvider);
  final provider = AiProvider.fromId(savedProvId);

  String host = AppConstants.defaultOllamaHost;
  String textModel = AppConstants.defaultTextTagModel;
  String embedModel = AppConstants.defaultEmbeddingModel;
  String apiKey = '';
  bool isFastApi = (provider == AiProvider.fastapi);

  switch (provider) {
    case AiProvider.ollama:
      host = prefs.getString(AppConstants.prefOllamaHost) ?? AppConstants.defaultOllamaHost;
      textModel = prefs.getString(AppConstants.prefTextModel) ?? AppConstants.defaultTextTagModel;
      embedModel = prefs.getString(AppConstants.prefEmbeddingModel) ?? AppConstants.defaultEmbeddingModel;
      break;
    case AiProvider.fastapi:
      host = prefs.getString(AppConstants.prefFastApiHost) ?? AppConstants.defaultFastApiHost;
      textModel = prefs.getString(AppConstants.prefTextModel) ?? AppConstants.defaultTextTagModel;
      embedModel = prefs.getString(AppConstants.prefEmbeddingModel) ?? AppConstants.defaultEmbeddingModel;
      isFastApi = true;
      break;
    case AiProvider.deepseek:
      host = prefs.getString(AppConstants.prefDeepSeekHost) ?? AppConstants.defaultDeepSeekHost;
      textModel = prefs.getString(AppConstants.prefDeepSeekModel) ?? AppConstants.defaultDeepSeekModel;
      apiKey = prefs.getString(AppConstants.prefDeepSeekApiKey) ?? '';
      break;
    case AiProvider.openai:
      host = prefs.getString(AppConstants.prefOpenAiHost) ?? AppConstants.defaultOpenAiHost;
      textModel = prefs.getString(AppConstants.prefOpenAiModel) ?? AppConstants.defaultOpenAiModel;
      embedModel = prefs.getString(AppConstants.prefOpenAiEmbeddingModel) ?? AppConstants.defaultOpenAiEmbeddingModel;
      apiKey = prefs.getString(AppConstants.prefOpenAiApiKey) ?? '';
      break;
    case AiProvider.claude:
      host = prefs.getString(AppConstants.prefClaudeHost) ?? AppConstants.defaultClaudeHost;
      textModel = prefs.getString(AppConstants.prefClaudeModel) ?? AppConstants.defaultClaudeModel;
      apiKey = prefs.getString(AppConstants.prefClaudeApiKey) ?? '';
      break;
    case AiProvider.google:
      host = prefs.getString(AppConstants.prefGoogleHost) ?? AppConstants.defaultGoogleHost;
      textModel = prefs.getString(AppConstants.prefGoogleModel) ?? AppConstants.defaultGoogleModel;
      embedModel = prefs.getString(AppConstants.prefGoogleEmbeddingModel) ?? AppConstants.defaultGoogleEmbeddingModel;
      apiKey = prefs.getString(AppConstants.prefGoogleApiKey) ?? '';
      break;
  }

  final diseaseClassificationMode = prefs.getBool(AppConstants.prefDiseaseClassificationMode) ?? true;

  // On desktop (Windows 11 / Linux), use SqliteDesktopDataSource for ACID persistence;
  // on Android, use KoreDbNativeDataSource for Kotlin KoreDB integration.
  // Both share identical JSON schema for seamless cross-platform backup and restore interoperability.
  final KoreDbDataSource dataSource;
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
    dataSource = SqliteDesktopDataSource();
  } else {
    dataSource = KoreDbNativeDataSource();
  }

  final repository = DocumentRepository(dataSource: dataSource);
  final ollamaClient = OllamaClient(
    provider: provider,
    host: host,
    textModel: textModel,
    embeddingModel: embedModel,
    apiKey: apiKey,
    isFastApi: isFastApi,
    diseaseClassificationMode: diseaseClassificationMode,
  );
  final importService = ImportService(
    repository: repository,
    dataSource: dataSource,
    ollamaClient: ollamaClient,
  );
  final searchService = HybridSearchService(
    dataSource: dataSource,
    ollamaClient: ollamaClient,
  );

  // Seed sample demonstration medical document if database is empty
  final allDocs = await repository.getAllDocuments();
  if (allDocs.isEmpty) {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final sampleFile = File('${appDir.path}/clinical_guidelines_diabetes_cardio.txt');
      if (!sampleFile.existsSync()) {
        await sampleFile.writeAsString('''Clinical Guidelines for Type 2 Diabetes Mellitus & Cardiovascular Risk Management
Chapter 1: Diagnostic Criteria and Pathophysiology
Type 2 Diabetes Mellitus (ICD-10: E11) is characterized by progressive beta-cell dysfunction and insulin resistance.
Patients presenting with chronic hyperglycemia and hypertension are at heightened risk of atherosclerotic cardiovascular disease (ICD-10: I25).

Chapter 2: Pharmacotherapy and Clinical Targets
1. Glycemic Target: HbA1c < 7.0% for most non-pregnant adults.
2. First-line agents: Metformin combined with SGLT2 inhibitors or GLP-1 receptor agonists.
3. Blood pressure threshold: < 130/80 mmHg.

Table 1: Recommended Disease Classification and ICD Mapping
- Type 2 Diabetes Mellitus: E11.9
- Atherosclerotic Heart Disease: I25.1
- Essential Primary Hypertension: I10
''');
      }

      final docId = 'sample-medical-doc-1';
      final now = DateTime.now().millisecondsSinceEpoch;
      final sampleDoc = Document(
        id: docId,
        title: 'Clinical Guidelines for Type 2 Diabetes Mellitus & Cardiovascular Risk Management',
        sourceType: 'pdf',
        filePath: sampleFile.path,
        fileHash: 'sample_medical_guidelines_hash',
        createdAt: now,
        updatedAt: now,
        pageCount: 1,
        language: 'en',
        tags: [
          TagItem(id: 'tag_med_1', name: '第2型糖尿病', category: '疾病/症狀', confidence: 0.98, source: 'ai_analysis', verified: true),
          TagItem(id: 'tag_med_2', name: '冠狀動脈心臟病', category: '疾病/症狀', confidence: 0.96, source: 'ai_analysis', verified: true),
          TagItem(id: 'tag_med_3', name: 'E11', category: '疾病分類編碼', confidence: 0.99, source: 'ai_analysis', verified: true),
          TagItem(id: 'tag_med_4', name: 'I25', category: '疾病分類編碼', confidence: 0.95, source: 'ai_analysis', verified: true),
          TagItem(id: 'tag_med_5', name: '胰島素阻抗', category: '醫學術語', confidence: 0.95, source: 'ai_analysis', verified: true),
          TagItem(id: 'tag_med_6', name: '糖化血色素(HbA1c)', category: '醫學術語', confidence: 0.94, source: 'ai_analysis', verified: true),
          TagItem(id: 'tag_med_7', name: 'SGLT2抑制劑', category: '醫學術語', confidence: 0.92, source: 'ai_analysis', verified: true),
          TagItem(id: 'tag_med_8', name: '臨床實證指引', category: '文檔類型', confidence: 1.0, source: 'ai_analysis', verified: true),
        ],
        summary: 'This clinical guidelines document outlines evidence-based recommendations for adult Type 2 Diabetes Mellitus patients with comorbid cardiovascular diseases. Highlights target HbA1c < 7.0%, blood pressure stabilization, and organ-protective pharmacotherapy using SGLT2 inhibitors.',
        metadata: {
          'chineseSummary': '【中文摘要說明】\n本篇英文臨床指引針對「第2型糖尿病 (ICD-10: E11)」合併「心血管動脈硬化疾病 (ICD-10: I25)」之成年患者提供實證處置建議。核心內容包括積極控制糖化血色素 (HbA1c < 7.0%)、優先選用具備心腎保護效益之 SGLT2 抑制劑，並調控血壓與胰島素阻抗。可作為內分泌代謝科、心臟科及疾病編碼對應之核心參考文獻。',
          'language': 'en',
        },
      );

      final page1 = PageItem(
        id: 'sample-med-page-1',
        documentId: docId,
        pageNumber: 1,
        imagePath: '',
        ocrText: await sampleFile.readAsString(),
        layoutBlocks: [
          LayoutBlock(type: 'title', bbox: [10, 10, 400, 40], text: 'Clinical Guidelines for Type 2 Diabetes Mellitus & Cardiovascular Risk Management'),
          LayoutBlock(type: 'paragraph', bbox: [10, 50, 400, 100], text: 'Chapter 1: Diagnostic Criteria and Pathophysiology\nType 2 Diabetes Mellitus (ICD-10: E11) is characterized by progressive beta-cell dysfunction and insulin resistance.'),
          LayoutBlock(type: 'table', bbox: [10, 160, 400, 260], text: 'Table 1: Recommended Disease Classification and ICD Mapping (E11.9, I25.1, I10)'),
        ],
      );

      await repository.saveDocument(sampleDoc);
      await repository.savePage(page1);
    } catch (e) {
      debugPrint('Error seeding sample document: $e');
    }
  }

  runApp(SmartDocSearchApp(
    repository: repository,
    ollamaClient: ollamaClient,
    importService: importService,
    searchService: searchService,
    initialDarkMode: isDarkMode,
  ));
}

class SmartDocSearchApp extends StatefulWidget {
  final DocumentRepository repository;
  final OllamaClient ollamaClient;
  final ImportService importService;
  final HybridSearchService searchService;
  final bool initialDarkMode;

  const SmartDocSearchApp({
    super.key,
    required this.repository,
    required this.ollamaClient,
    required this.importService,
    required this.searchService,
    required this.initialDarkMode,
  });

  @override
  State<SmartDocSearchApp> createState() => _SmartDocSearchAppState();
}

class _SmartDocSearchAppState extends State<SmartDocSearchApp> {
  late bool _isDarkMode;

  @override
  void initState() {
    super.initState();
    _isDarkMode = widget.initialDarkMode;
  }

  void _toggleTheme(bool dark) async {
    setState(() => _isDarkMode = dark);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.prefDarkMode, dark);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '個人智能文獻檢索',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: MainNavigationShell(
        repository: widget.repository,
        ollamaClient: widget.ollamaClient,
        importService: widget.importService,
        searchService: widget.searchService,
        isDarkMode: _isDarkMode,
        onThemeChanged: _toggleTheme,
      ),
    );
  }
}

class MainNavigationShell extends StatefulWidget {
  final DocumentRepository repository;
  final OllamaClient ollamaClient;
  final ImportService importService;
  final HybridSearchService searchService;
  final bool isDarkMode;
  final Function(bool) onThemeChanged;

  const MainNavigationShell({
    super.key,
    required this.repository,
    required this.ollamaClient,
    required this.importService,
    required this.searchService,
    required this.isDarkMode,
    required this.onThemeChanged,
  });

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  int _currentIndex = 0;
  String? _prefilledSearchQuery;

  void _onNavigateTab(int index) {
    setState(() {
      _currentIndex = index;
    });
    widget.repository.notifyDataChanged(immediate: true);
  }

  void _onQuickSearch(String query) {
    setState(() {
      _prefilledSearchQuery = query;
      _currentIndex = 1; // Search tab
    });
    widget.repository.notifyDataChanged(immediate: true);
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      HomeScreen(
        repository: widget.repository,
        ollamaClient: widget.ollamaClient,
        onNavigateTab: _onNavigateTab,
        onQuickSearch: _onQuickSearch,
      ),
      SearchScreen(
        key: ValueKey(_prefilledSearchQuery ?? 'search_screen'),
        repository: widget.repository,
        ollamaClient: widget.ollamaClient,
        searchService: widget.searchService,
        initialQuery: _prefilledSearchQuery,
      ),
      ImportScreen(
        importService: widget.importService,
        onImportSuccess: () {
          widget.repository.notifyDataChanged(immediate: true);
        },
      ),
      TagManagementScreen(
        repository: widget.repository,
      ),
      SettingsScreen(
        repository: widget.repository,
        ollamaClient: widget.ollamaClient,
        isDarkMode: widget.isDarkMode,
        onThemeChanged: widget.onThemeChanged,
      ),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) {
          setState(() {
            if (idx != 1) _prefilledSearchQuery = null;
            _currentIndex = idx;
          });
          widget.repository.notifyDataChanged(immediate: true);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '首頁',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search),
            label: '檢索',
          ),
          NavigationDestination(
            icon: Icon(Icons.cloud_upload_outlined),
            selectedIcon: Icon(Icons.cloud_upload),
            label: '匯入',
          ),
          NavigationDestination(
            icon: Icon(Icons.label_outline),
            selectedIcon: Icon(Icons.label),
            label: '標籤',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '設定',
          ),
        ],
      ),
    );
  }
}
