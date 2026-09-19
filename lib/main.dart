import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_doc_search/core/constants/app_constants.dart';
import 'package:smart_doc_search/core/theme/app_theme.dart';
import 'package:smart_doc_search/data/datasources/koredb_datasource.dart';
import 'package:smart_doc_search/data/datasources/ollama_client.dart';
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
  final ollamaHost = prefs.getString(AppConstants.prefOllamaHost) ?? AppConstants.defaultOllamaHost;
  final textModel = prefs.getString(AppConstants.prefTextModel) ?? AppConstants.defaultTextTagModel;
  final embedModel = prefs.getString(AppConstants.prefEmbeddingModel) ?? AppConstants.defaultEmbeddingModel;
  final isFastApi = prefs.getBool(AppConstants.prefFastApiEnabled) ?? false;

  final dataSource = KoreDbNativeDataSource();
  final repository = DocumentRepository(dataSource: dataSource);
  final ollamaClient = OllamaClient(
    host: ollamaHost,
    textModel: textModel,
    embeddingModel: embedModel,
    isFastApi: isFastApi,
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
  }

  void _onQuickSearch(String query) {
    setState(() {
      _prefilledSearchQuery = query;
      _currentIndex = 1; // Search tab
    });
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
          // After import, user can see results
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
