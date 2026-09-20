import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_doc_search/core/constants/app_constants.dart';
import 'package:smart_doc_search/core/theme/app_theme.dart';
import 'package:smart_doc_search/core/utils/security_util.dart';
import 'package:smart_doc_search/data/datasources/ollama_client.dart';
import 'package:smart_doc_search/data/models/document_model.dart';
import 'package:smart_doc_search/data/repositories/document_repository.dart';
import 'package:smart_doc_search/features/analysis/ai_analysis_service.dart';
import 'package:smart_doc_search/features/document/document_detail_screen.dart';

/// Screen for independent AI text and document analysis, multi-dimensional
/// tag generation, weighted document relevance search, and official document import.
class AiAnalysisScreen extends StatefulWidget {
  final DocumentRepository repository;
  final OllamaClient ollamaClient;
  final VoidCallback? onNavigateToSettings;

  const AiAnalysisScreen({
    super.key,
    required this.repository,
    required this.ollamaClient,
    this.onNavigateToSettings,
  });

  @override
  State<AiAnalysisScreen> createState() => _AiAnalysisScreenState();
}

class _AiAnalysisScreenState extends State<AiAnalysisScreen> {
  late final AiAnalysisService _analysisService;

  // Input & file controllers
  final TextEditingController _textCtrl = TextEditingController();
  final TextEditingController _customPromptCtrl = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  LoadedTextFile? _loadedFile;
  int _charCount = 0;
  bool _showCustomPrompt = false;

  // Provider state
  late AiProvider _currentProvider;
  bool _isCheckingConnection = false;
  bool? _isProviderOnline;

  // Analysis execution state
  bool _isAnalyzing = false;
  CancelToken? _cancelToken;
  Stopwatch? _stopwatch;
  Timer? _timer;
  int _elapsedMs = 0;

  // Analysis results
  AiAnalysisResult? _analysisResult;
  List<TagItem> _currentTags = [];
  String _usedModel = '';
  int _analysisDurationMs = 0;

  // Relevant document search state
  String _searchMode = 'WEIGHTED'; // 'WEIGHTED', 'AND', 'OR'
  bool _isSearchingDocs = false;
  List<AiDocumentMatch> _relevantDocs = [];

  // History count
  int _historyCount = 0;

  @override
  void initState() {
    super.initState();
    _analysisService = AiAnalysisService(
      repository: widget.repository,
      ollamaClient: widget.ollamaClient,
    );
    _currentProvider = widget.ollamaClient.provider;

    _textCtrl.addListener(() {
      setState(() {
        _charCount = _textCtrl.text.length;
      });
    });

    _checkConnection();
    _loadHistoryCount();
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    _timer?.cancel();
    _textCtrl.dispose();
    _customPromptCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadHistoryCount() async {
    final list = await _analysisService.loadHistory();
    if (mounted) {
      setState(() => _historyCount = list.length);
    }
  }

  Future<void> _checkConnection() async {
    if (!mounted) return;
    setState(() => _isCheckingConnection = true);
    final online = await widget.ollamaClient.testConnection();
    if (mounted) {
      setState(() {
        _isCheckingConnection = false;
        _isProviderOnline = online;
      });
    }
  }

  bool _isApiKeyRequired(AiProvider prov) {
    return prov == AiProvider.openai ||
        prov == AiProvider.claude ||
        prov == AiProvider.google ||
        prov == AiProvider.deepseek;
  }

  bool _isApiKeyConfigured(AiProvider prov) {
    if (!_isApiKeyRequired(prov)) return true;
    return widget.ollamaClient.apiKey.trim().isNotEmpty;
  }

  Future<void> _onProviderChanged(AiProvider prov) async {
    setState(() {
      _currentProvider = prov;
      widget.ollamaClient.provider = prov;
      widget.ollamaClient.isFastApi = (prov == AiProvider.fastapi);
    });

    // Load provider config from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.prefAiProvider, prov.id);

    switch (prov) {
      case AiProvider.ollama:
        widget.ollamaClient.host = prefs.getString(AppConstants.prefOllamaHost) ?? AppConstants.defaultOllamaHost;
        widget.ollamaClient.textModel = prefs.getString(AppConstants.prefTextModel) ?? AppConstants.defaultTextTagModel;
        widget.ollamaClient.apiKey = '';
        break;
      case AiProvider.fastapi:
        widget.ollamaClient.host = prefs.getString(AppConstants.prefFastApiHost) ?? AppConstants.defaultFastApiHost;
        widget.ollamaClient.textModel = prefs.getString(AppConstants.prefTextModel) ?? AppConstants.defaultTextTagModel;
        widget.ollamaClient.apiKey = '';
        break;
      case AiProvider.deepseek:
        widget.ollamaClient.host = prefs.getString(AppConstants.prefDeepSeekHost) ?? AppConstants.defaultDeepSeekHost;
        widget.ollamaClient.textModel = prefs.getString(AppConstants.prefDeepSeekModel) ?? AppConstants.defaultDeepSeekModel;
        widget.ollamaClient.apiKey = SecurityUtil.getDecryptedKey(prefs, AppConstants.prefDeepSeekApiKey);
        break;
      case AiProvider.openai:
        widget.ollamaClient.host = prefs.getString(AppConstants.prefOpenAiHost) ?? AppConstants.defaultOpenAiHost;
        widget.ollamaClient.textModel = prefs.getString(AppConstants.prefOpenAiModel) ?? AppConstants.defaultOpenAiModel;
        widget.ollamaClient.apiKey = SecurityUtil.getDecryptedKey(prefs, AppConstants.prefOpenAiApiKey);
        break;
      case AiProvider.claude:
        widget.ollamaClient.host = prefs.getString(AppConstants.prefClaudeHost) ?? AppConstants.defaultClaudeHost;
        widget.ollamaClient.textModel = prefs.getString(AppConstants.prefClaudeModel) ?? AppConstants.defaultClaudeModel;
        widget.ollamaClient.apiKey = SecurityUtil.getDecryptedKey(prefs, AppConstants.prefClaudeApiKey);
        break;
      case AiProvider.google:
        widget.ollamaClient.host = prefs.getString(AppConstants.prefGoogleHost) ?? AppConstants.defaultGoogleHost;
        widget.ollamaClient.textModel = prefs.getString(AppConstants.prefGoogleModel) ?? AppConstants.defaultGoogleModel;
        widget.ollamaClient.apiKey = SecurityUtil.getDecryptedKey(prefs, AppConstants.prefGoogleApiKey);
        break;
    }

    _checkConnection();
  }

  // 1. Text actions: Paste, Load File, Clear
  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    if (data?.text != null && data!.text!.isNotEmpty) {
      _textCtrl.text = data.text!;
      setState(() => _loadedFile = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已自剪貼簿貼上文字'), duration: Duration(seconds: 1)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('剪貼簿中無純文字內容'), duration: Duration(seconds: 2)),
      );
    }
  }

  Future<void> _pickFile() async {
    try {
      final loaded = await _analysisService.pickTextFile();
      if (!mounted) return;
      if (loaded != null) {
        setState(() {
          _loadedFile = loaded;
          _textCtrl.text = loaded.content;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已成功載入檔案：${loaded.fileName} (${loaded.formattedSize})'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog('檔案載入失敗', e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  void _clearInput() {
    setState(() {
      _textCtrl.clear();
      _loadedFile = null;
      _analysisResult = null;
      _currentTags = [];
      _relevantDocs = [];
    });
  }

  // 2. Start AI Analysis
  Future<void> _startAnalysis() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;

    if (_isApiKeyRequired(_currentProvider) && !_isApiKeyConfigured(_currentProvider)) {
      _showApiKeyMissingDialog();
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _cancelToken = CancelToken();
      _elapsedMs = 0;
      _stopwatch = Stopwatch()..start();
    });

    _timer = Timer.periodic(const Duration(milliseconds: 100), (t) {
      if (mounted && _stopwatch != null) {
        setState(() => _elapsedMs = _stopwatch!.elapsedMilliseconds);
      }
    });

    try {
      final customPrompt = _customPromptCtrl.text.trim();
      final result = await widget.ollamaClient.generateAnalysis(
        text: text,
        customPrompt: customPrompt.isNotEmpty ? customPrompt : null,
        cancelToken: _cancelToken,
      );

      _stopwatch?.stop();
      _timer?.cancel();

      if (!mounted) return;

      final duration = _stopwatch?.elapsedMilliseconds ?? _elapsedMs;
      final activeModel = widget.ollamaClient.textModel;

      setState(() {
        _isAnalyzing = false;
        _analysisResult = result;
        _currentTags = List<TagItem>.from(result.tags);
        _usedModel = activeModel;
        _analysisDurationMs = duration;
      });

      // Save to history
      final historyItem = AiAnalysisHistoryItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        timestamp: DateTime.now().millisecondsSinceEpoch,
        textSnippet: text.length > 150 ? '${text.substring(0, 147)}...' : text,
        fullText: text,
        tags: _currentTags,
        summary: result.summary,
        chineseSummary: result.chineseSummary,
        provider: widget.ollamaClient.providerDisplayName,
        model: activeModel,
        durationMs: duration,
      );
      await _analysisService.saveHistory(historyItem);
      _loadHistoryCount();

      // Automatically query relevant documents from database using generated tags
      await _performRelevantSearch();
    } catch (e) {
      _stopwatch?.stop();
      _timer?.cancel();

      if (!mounted) return;
      setState(() => _isAnalyzing = false);

      if (e is DioException && e.type == DioExceptionType.cancel) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已取消 AI 分析'), duration: Duration(seconds: 2)),
        );
        return;
      }

      final friendlyMsg = widget.ollamaClient.getFriendlyErrorMessage(e);
      _showErrorDialog('AI 分析失敗', friendlyMsg, allowRetry: true);
    }
  }

  void _cancelAnalysis() {
    _cancelToken?.cancel();
    _stopwatch?.stop();
    _timer?.cancel();
    setState(() => _isAnalyzing = false);
  }

  // 3. Search relevant documents
  Future<void> _performRelevantSearch() async {
    if (_currentTags.isEmpty) {
      setState(() => _relevantDocs = []);
      return;
    }

    setState(() => _isSearchingDocs = true);
    try {
      final matches = await _analysisService.searchRelevantDocuments(
        queryTags: _currentTags,
        mode: _searchMode,
      );
      if (mounted) {
        setState(() {
          _relevantDocs = matches;
          _isSearchingDocs = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSearchingDocs = false);
      }
    }
  }

  // 4. Tag editing & manipulation
  void _removeTag(TagItem tag) {
    setState(() {
      _currentTags.removeWhere((t) => t.name == tag.name);
    });
    _performRelevantSearch();
  }

  void _showAddTagDialog() {
    final nameCtrl = TextEditingController();
    String category = '主題';
    double confidence = 0.95;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('新增檢索標籤'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: '標籤名稱',
                    hintText: '例如：第二型糖尿病、CNN',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  decoration: const InputDecoration(
                    labelText: '標籤維度 / 分類',
                    border: OutlineInputBorder(),
                  ),
                  items: AppConstants.defaultTagDimensions
                      .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setDialogState(() => category = val);
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('信心度：'),
                    Text('${(confidence * 100).round()}%',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                Slider(
                  value: confidence,
                  min: 0.1,
                  max: 1.0,
                  divisions: 18,
                  onChanged: (val) => setDialogState(() => confidence = val),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameCtrl.text.trim();
                if (name.isNotEmpty) {
                  setState(() {
                    _currentTags.add(TagItem(
                      id: 'tag_custom_${DateTime.now().millisecondsSinceEpoch}',
                      name: name,
                      category: category,
                      confidence: confidence,
                      source: 'user_added',
                    ));
                  });
                  Navigator.pop(ctx);
                  _performRelevantSearch();
                }
              },
              child: const Text('加入並檢索'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditTagDialog(TagItem tag, int index) {
    final nameCtrl = TextEditingController(text: tag.name);
    String category = AppConstants.defaultTagDimensions.contains(tag.category)
        ? tag.category
        : AppConstants.defaultTagDimensions.first;
    double confidence = tag.confidence;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('編輯標籤'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: '標籤名稱',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  decoration: const InputDecoration(
                    labelText: '標籤維度 / 分類',
                    border: OutlineInputBorder(),
                  ),
                  items: AppConstants.defaultTagDimensions
                      .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setDialogState(() => category = val);
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('信心度：'),
                    Text('${(confidence * 100).round()}%',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                Slider(
                  value: confidence,
                  min: 0.1,
                  max: 1.0,
                  divisions: 18,
                  onChanged: (val) => setDialogState(() => confidence = val),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameCtrl.text.trim();
                if (name.isNotEmpty) {
                  setState(() {
                    _currentTags[index] = tag.copyWith(
                      name: name,
                      category: category,
                      confidence: confidence,
                    );
                  });
                  Navigator.pop(ctx);
                  _performRelevantSearch();
                }
              },
              child: const Text('更新並檢索'),
            ),
          ],
        ),
      ),
    );
  }

  // 5. Import as Official Document (FR-C-07)
  Future<void> _importAsDocument() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;

    final defaultTitle = _loadedFile?.fileName ??
        (text.split('\n').first.trim().isNotEmpty
            ? (text.split('\n').first.trim().length > 40
                ? '${text.split('\n').first.trim().substring(0, 37)}...'
                : text.split('\n').first.trim())
            : 'AI 分析文檔 - ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}');

    final titleCtrl = TextEditingController(text: defaultTitle);
    bool clearAfterImport = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.save_alt, color: AppTheme.primaryColor),
              SizedBox(width: 8),
              Text('匯入為正式文獻'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('將本次文字內容、AI 摘要與多維標籤儲存為正式文獻：'),
                const SizedBox(height: 16),
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(
                    labelText: '文獻標題',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Text('標籤數：${_currentTags.length} 個',
                    style: const TextStyle(fontSize: 13, color: Colors.grey)),
                Text('字數：${text.length} 字元',
                    style: const TextStyle(fontSize: 13, color: Colors.grey)),
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: clearAfterImport,
                  title: const Text('匯入成功後清空分析輸入框', style: TextStyle(fontSize: 14)),
                  onChanged: (val) => setDialogState(() => clearAfterImport = val ?? false),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('確認匯入'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    try {
      final doc = await _analysisService.importFromAnalysis(
        text: text,
        tags: _currentTags,
        summary: _analysisResult?.summary ?? '',
        chineseSummary: _analysisResult?.chineseSummary,
        customTitle: titleCtrl.text.trim(),
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('文獻「${doc.title}」已成功匯入！'),
          backgroundColor: Colors.green,
          action: SnackBarAction(
            label: '查看文獻',
            textColor: Colors.white,
            onPressed: () => _openDocumentDetail(doc.id),
          ),
        ),
      );

      if (clearAfterImport) {
        _clearInput();
      } else {
        // Re-run search to see newly imported document in relevant matches!
        _performRelevantSearch();
      }
    } catch (e) {
      _showErrorDialog('匯入失敗', e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _openDocumentDetail(String docId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => DocumentDetailScreen(
          documentId: docId,
          repository: widget.repository,
          ollamaClient: widget.ollamaClient,
        ),
      ),
    );
  }

  // 6. History Management (FR-C-08)
  Future<void> _showHistoryDialog() async {
    final history = await _analysisService.loadHistory();
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (ctx, scrollCtrl) => Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.history, color: AppTheme.primaryColor),
                    const SizedBox(width: 8),
                    Text('分析歷史記錄 (${history.length}/20)',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    if (history.isNotEmpty)
                      TextButton.icon(
                        icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                        label: const Text('清空記錄', style: TextStyle(color: Colors.red)),
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (c) => AlertDialog(
                              title: const Text('清空歷史記錄'),
                              content: const Text('確定要清除所有分析歷史記錄嗎？此動作無法復原。'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
                                FilledButton(
                                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                  onPressed: () => Navigator.pop(c, true),
                                  child: const Text('確認清除'),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            await _analysisService.clearAllHistory();
                            setModalState(() => history.clear());
                            setState(() => _historyCount = 0);
                            if (mounted && ctx.mounted) Navigator.pop(ctx);
                          }
                        },
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: history.isEmpty
                    ? const Center(
                        child: Text('尚無歷史分析記錄', style: TextStyle(color: Colors.grey)),
                      )
                    : ListView.separated(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.all(16),
                        itemCount: history.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (ctx, idx) {
                          final item = history[idx];
                          final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(
                            DateTime.fromMillisecondsSinceEpoch(item.timestamp),
                          );
                          return Card(
                            elevation: 1,
                            child: ListTile(
                              contentPadding: const EdgeInsets.all(12),
                              title: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.primaryContainer,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      item.model,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(dateStr, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                  const Spacer(),
                                  Text('${(item.durationMs / 1000).toStringAsFixed(1)}s',
                                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 8),
                                  Text(item.textSnippet,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13)),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 4,
                                    runSpacing: 4,
                                    children: item.tags.take(5).map((t) {
                                      return Chip(
                                        label: Text(t.name, style: const TextStyle(fontSize: 11)),
                                        visualDensity: VisualDensity.compact,
                                        padding: EdgeInsets.zero,
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline, size: 20),
                                onPressed: () async {
                                  await _analysisService.deleteHistoryItem(item.id);
                                  setModalState(() => history.removeAt(idx));
                                  _loadHistoryCount();
                                },
                              ),
                              onTap: () {
                                Navigator.pop(ctx);
                                _restoreFromHistory(item);
                              },
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

  void _restoreFromHistory(AiAnalysisHistoryItem item) {
    setState(() {
      _textCtrl.text = item.fullText;
      _loadedFile = null;
      _analysisResult = AiAnalysisResult(
        tags: item.tags,
        summary: item.summary,
        chineseSummary: item.chineseSummary,
      );
      _currentTags = List<TagItem>.from(item.tags);
      _usedModel = item.model;
      _analysisDurationMs = item.durationMs;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已載入歷史分析記錄'), duration: Duration(seconds: 1)),
    );

    _performRelevantSearch();
  }

  void _showApiKeyMissingDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.key, color: Colors.amber),
            SizedBox(width: 8),
            Text('需要設定 API KEY'),
          ],
        ),
        content: Text(
          '目前選擇的 Provider（${_currentProvider.displayName}）需要設定有效的 API KEY 才能呼叫雲端模型。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('稍後'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.settings),
            label: const Text('前往設定頁'),
            onPressed: () {
              Navigator.pop(ctx);
              if (widget.onNavigateToSettings != null) {
                widget.onNavigateToSettings!();
              }
            },
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String title, String message, {bool allowRetry = false}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('關閉'),
          ),
          if (allowRetry)
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _startAnalysis();
              },
              child: const Text('重試'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.psychology, color: AppTheme.primaryColor),
            SizedBox(width: 8),
            Text('AI 分析', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        actions: [
          // History Button
          IconButton(
            tooltip: '歷史分析記錄',
            icon: Badge(
              isLabelVisible: _historyCount > 0,
              label: Text('$_historyCount'),
              child: const Icon(Icons.history),
            ),
            onPressed: _showHistoryDialog,
          ),
          // Clear All Button
          IconButton(
            tooltip: '清空頁面',
            icon: const Icon(Icons.cleaning_services_outlined),
            onPressed: (_textCtrl.text.isNotEmpty || _analysisResult != null) ? _clearInput : null,
          ),
          // Settings button
          if (widget.onNavigateToSettings != null)
            IconButton(
              tooltip: 'AI 設定',
              icon: const Icon(Icons.settings_outlined),
              onPressed: widget.onNavigateToSettings,
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 900;
          if (isWide) {
            // Wide Screen: Dual Column Layout (Left: Input & Analysis, Right: Relevant Docs)
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 5,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildProviderSelectorCard(),
                      const SizedBox(height: 16),
                      _buildInputCard(),
                      if (_analysisResult != null || _isAnalyzing) ...[
                        const SizedBox(height: 16),
                        _buildAnalysisResultCard(),
                      ],
                    ],
                  ),
                ),
                const VerticalDivider(width: 1, thickness: 1),
                Expanded(
                  flex: 5,
                  child: _buildRelevantDocumentsSection(),
                ),
              ],
            );
          }

          // Single Column Layout for Mobile
          return ListView(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            children: [
              _buildProviderSelectorCard(),
              const SizedBox(height: 16),
              _buildInputCard(),
              if (_analysisResult != null || _isAnalyzing) ...[
                const SizedBox(height: 16),
                _buildAnalysisResultCard(),
                const SizedBox(height: 16),
                _buildRelevantDocumentsSection(isEmbedded: true),
              ],
            ],
          );
        },
      ),
    );
  }

  // Widget: Provider Selector Card
  Widget _buildProviderSelectorCard() {
    final isOnline = _isProviderOnline == true;
    final isKeyConfigured = _isApiKeyConfigured(_currentProvider);

    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.hub_outlined, size: 20, color: AppTheme.primaryColor),
            const SizedBox(width: 8),
            const Text('Provider：', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<AiProvider>(
                  isDense: true,
                  isExpanded: true,
                  value: _currentProvider,
                  items: [
                    AiProvider.ollama,
                    AiProvider.openai,
                    AiProvider.claude,
                    AiProvider.google,
                    AiProvider.deepseek,
                    AiProvider.fastapi,
                  ].map((p) {
                    return DropdownMenuItem(
                      value: p,
                      child: Text(
                        p.displayName,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (p) {
                    if (p != null) _onProviderChanged(p);
                  },
                ),
              ),
            ),
            if (!isKeyConfigured)
              InkWell(
                onTap: _showApiKeyMissingDialog,
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.amber.shade700),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.key, size: 13, color: Colors.amber.shade800),
                      const SizedBox(width: 4),
                      Text('未設定 Key',
                          style: TextStyle(fontSize: 11, color: Colors.amber.shade900, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              )
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isCheckingConnection)
                    const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  else
                    Tooltip(
                      message: isOnline ? '服務在線' : '服務連線失敗',
                      child: Row(
                        children: [
                          Icon(Icons.circle, size: 10, color: isOnline ? Colors.green : Colors.grey),
                          const SizedBox(width: 4),
                          Text(
                            isOnline ? '在線' : '離線',
                            style: TextStyle(fontSize: 11, color: isOnline ? Colors.green : Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 18),
                    tooltip: '重新測試連線',
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                    onPressed: _checkConnection,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // Widget: Input Card
  Widget _buildInputCard() {
    final isOverLimit = _charCount > AiAnalysisService.maxTextLength;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Loaded file badge if present
            if (_loadedFile != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.description, size: 18, color: AppTheme.primaryColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${_loadedFile!.fileName} (${_loadedFile!.formattedSize})',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () => setState(() => _loadedFile = null),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),

            // Text input field
            TextField(
              controller: _textCtrl,
              minLines: 5,
              maxLines: 12,
              decoration: InputDecoration(
                hintText: '輸入文字、貼上臨床指南、病歷紀錄或載入純文字檔案...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                contentPadding: const EdgeInsets.all(14),
              ),
            ),

            const SizedBox(height: 8),

            // Word counter & buttons row
            Row(
              children: [
                Text(
                  '字數：${NumberFormat('#,###').format(_charCount)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isOverLimit ? Colors.red : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (isOverLimit) ...[
                  const SizedBox(width: 6),
                  const Text('（建議分段）', style: TextStyle(fontSize: 11, color: Colors.red)),
                ],
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.paste, size: 16),
                  label: const Text('貼上', style: TextStyle(fontSize: 12)),
                  onPressed: _pasteFromClipboard,
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.folder_open, size: 16),
                  label: const Text('載入檔案', style: TextStyle(fontSize: 12)),
                  onPressed: _pickFile,
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.clear_all, size: 16),
                  label: const Text('清空', style: TextStyle(fontSize: 12)),
                  onPressed: _textCtrl.text.isNotEmpty ? () => setState(() => _textCtrl.clear()) : null,
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                ),
              ],
            ),

            if (isOverLimit) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.red, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '文字超過上限（50,000 字元），可能導致模型截斷或逾時，建議分段分析。',
                        style: TextStyle(fontSize: 12, color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Custom Prompt Accordion
            const SizedBox(height: 6),
            InkWell(
              onTap: () => setState(() => _showCustomPrompt = !_showCustomPrompt),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(_showCustomPrompt ? Icons.expand_less : Icons.expand_more, size: 18, color: Colors.grey),
                    const SizedBox(width: 4),
                    const Text('自訂分析提示詞（進階選項）', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
            ),
            if (_showCustomPrompt) ...[
              const SizedBox(height: 6),
              TextField(
                controller: _customPromptCtrl,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: '例如：特別強化神經退化性疾病分類與 ICD-10 編碼對照，摘要需以臨床決策為導向...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.all(10),
                  filled: true,
                ),
              ),
            ],

            const SizedBox(height: 14),

            // Start Analysis Action
            if (_isAnalyzing)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      label: Text('AI 深度分析中... (${(_elapsedMs / 1000).toStringAsFixed(1)}s)'),
                      onPressed: null,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.stop),
                    label: const Text('取消'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.red.withValues(alpha: 0.15),
                      foregroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                    ),
                    onPressed: _cancelAnalysis,
                  ),
                ],
              )
            else
              FilledButton.icon(
                icon: const Icon(Icons.auto_awesome),
                label: const Text('開始分析', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                onPressed: _charCount > 0 ? _startAnalysis : null,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Widget: Analysis Result Card (Tags + Summary)
  Widget _buildAnalysisResultCard() {
    if (_analysisResult == null) return const SizedBox.shrink();

    final result = _analysisResult!;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Row: Model & Elapsed Time Badge
            Row(
              children: [
                const Icon(Icons.insights, color: AppTheme.primaryColor),
                const SizedBox(width: 8),
                const Text('分析結果', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '模型：$_usedModel',
                    style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onPrimaryContainer),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '耗時：${(_analysisDurationMs / 1000).toStringAsFixed(1)}s',
                    style: const TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // Chinese Summary Callout (if available)
            if (result.chineseSummary.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF1A2634)
                      : const Color(0xFFEBF3FB),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF2E4562)
                        : const Color(0xFFBCE0FD),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.translate, size: 16, color: Colors.blue),
                        const SizedBox(width: 6),
                        const Text('【核心摘要與中文說明】',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blue)),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.copy, size: 16),
                          tooltip: '複製中文說明',
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: result.chineseSummary));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('已複製中文說明'), duration: Duration(seconds: 1)),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    SelectableText(
                      result.chineseSummary,
                      style: const TextStyle(fontSize: 13, height: 1.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Executive Summary
            if (result.summary.isNotEmpty && result.summary != result.chineseSummary) ...[
              const Text('摘要說明：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SelectableText(
                  result.summary,
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
              ),
              const SizedBox(height: 14),
            ],

            // Multi-dimensional Tags Header
            Row(
              children: [
                const Icon(Icons.label, size: 18, color: AppTheme.primaryColor),
                const SizedBox(width: 6),
                Text('多維標籤 (${_currentTags.length})',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('新增標籤', style: TextStyle(fontSize: 12)),
                  onPressed: _showAddTagDialog,
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Tag Chips Grid / Wrap
            if (_currentTags.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('無分析標籤', style: TextStyle(color: Colors.grey)),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(_currentTags.length, (idx) {
                  final tag = _currentTags[idx];
                  final isMed = tag.category == '疾病分類編碼' || tag.category == '疾病/症狀';
                  final chipColor = isMed
                      ? Colors.red.withValues(alpha: 0.1)
                      : Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3);

                  return InkWell(
                    onTap: () => _showEditTagDialog(tag, idx),
                    borderRadius: BorderRadius.circular(8),
                    child: Chip(
                      backgroundColor: chipColor,
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '[${tag.category}] ',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isMed ? Colors.red : Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          Text(
                            tag.name,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${(tag.confidence * 100).round()}%',
                            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                      deleteIcon: const Icon(Icons.close, size: 15),
                      onDeleted: () => _removeTag(tag),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    ),
                  );
                }),
              ),

            const SizedBox(height: 16),

            // Action Buttons Row: Re-search & Import
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.refresh),
                    label: const Text('重新檢索'),
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                    onPressed: _currentTags.isNotEmpty ? _performRelevantSearch : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.save_alt),
                    label: const Text('匯入為文檔'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.teal.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _importAsDocument,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Widget: Relevant Documents Section (FR-C-05)
  Widget _buildRelevantDocumentsSection({bool isEmbedded = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header & Mode Selector
        Padding(
          padding: EdgeInsets.symmetric(horizontal: isEmbedded ? 0 : 16, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.menu_book, color: AppTheme.primaryColor),
              const SizedBox(width: 8),
              Text(
                '相關文獻 (${_relevantDocs.length} 篇)',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              // Segmented Button for Mode
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'WEIGHTED', label: Text('加權', style: TextStyle(fontSize: 12))),
                  ButtonSegment(value: 'OR', label: Text('任一', style: TextStyle(fontSize: 12))),
                  ButtonSegment(value: 'AND', label: Text('全部', style: TextStyle(fontSize: 12))),
                ],
                selected: {_searchMode},
                onSelectionChanged: (set) {
                  setState(() => _searchMode = set.first);
                  _performRelevantSearch();
                },
              ),
            ],
          ),
        ),

        const SizedBox(height: 6),

        if (_isSearchingDocs)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_analysisResult == null && _currentTags.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.psychology_alt_outlined, size: 60, color: Colors.grey.withValues(alpha: 0.5)),
                  const SizedBox(height: 12),
                  const Text('輸入文字並點擊「開始分析」\n自動檢索庫內相關文獻',
                      textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, height: 1.4)),
                ],
              ),
            ),
          )
        else if (_relevantDocs.isEmpty)
          Card(
            margin: EdgeInsets.symmetric(horizontal: isEmbedded ? 0 : 16, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.find_in_page_outlined, size: 48, color: Colors.grey.withValues(alpha: 0.6)),
                  const SizedBox(height: 12),
                  const Text(
                    '尚無相關文獻',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '文獻庫中尚未有匹配本次標籤之檔案。是否將本次分析結果直接匯入為新文獻？',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('匯入為新文獻'),
                    onPressed: _importAsDocument,
                  ),
                ],
              ),
            ),
          )
        else
          Expanded(
            flex: isEmbedded ? 0 : 1,
            child: ListView.separated(
              shrinkWrap: isEmbedded,
              physics: isEmbedded ? const NeverScrollableScrollPhysics() : null,
              padding: EdgeInsets.symmetric(horizontal: isEmbedded ? 0 : 16, vertical: 8),
              itemCount: _relevantDocs.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (ctx, idx) {
                final match = _relevantDocs[idx];
                final doc = match.document;
                final scorePct = match.scorePercent;

                // Color based on score
                Color scoreColor = Colors.orange;
                if (scorePct >= 80) {
                  scoreColor = Colors.green;
                } else if (scorePct >= 50) {
                  scoreColor = Colors.blue;
                }

                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => _openDocumentDetail(doc.id),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: scoreColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: scoreColor.withValues(alpha: 0.4)),
                                ),
                                child: Text(
                                  '相關度 $scorePct%',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: scoreColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  doc.title,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (doc.summary.isNotEmpty)
                            Text(
                              doc.summary,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                height: 1.3,
                              ),
                            ),
                          const SizedBox(height: 8),
                          // Matched tags
                          Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: match.matchedTags.map((t) {
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.check, size: 12, color: AppTheme.primaryColor),
                                    const SizedBox(width: 2),
                                    Text(t, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
