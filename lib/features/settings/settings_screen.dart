import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_doc_search/core/constants/app_constants.dart';
import 'package:smart_doc_search/data/datasources/ollama_client.dart';
import 'package:smart_doc_search/data/repositories/document_repository.dart';

class SettingsScreen extends StatefulWidget {
  final DocumentRepository repository;
  final OllamaClient ollamaClient;
  final Function(bool) onThemeChanged;
  final bool isDarkMode;

  const SettingsScreen({
    super.key,
    required this.repository,
    required this.ollamaClient,
    required this.onThemeChanged,
    required this.isDarkMode,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  AiProvider _selectedProvider = AiProvider.ollama;

  // Controllers per Provider
  final TextEditingController _ollamaHostCtrl = TextEditingController();
  final TextEditingController _fastApiHostCtrl = TextEditingController();

  final TextEditingController _deepSeekKeyCtrl = TextEditingController();
  final TextEditingController _deepSeekHostCtrl = TextEditingController();

  final TextEditingController _openAiKeyCtrl = TextEditingController();
  final TextEditingController _openAiHostCtrl = TextEditingController();

  final TextEditingController _claudeKeyCtrl = TextEditingController();
  final TextEditingController _claudeHostCtrl = TextEditingController();

  final TextEditingController _googleKeyCtrl = TextEditingController();
  final TextEditingController _googleHostCtrl = TextEditingController();

  // Selected Models per Provider
  String _ollamaTextModel = AppConstants.defaultTextTagModel;
  String _ollamaEmbeddingModel = AppConstants.defaultEmbeddingModel;

  String _deepSeekModel = AppConstants.defaultDeepSeekModel;

  String _openAiModel = AppConstants.defaultOpenAiModel;
  String _openAiEmbeddingModel = AppConstants.defaultOpenAiEmbeddingModel;

  String _claudeModel = AppConstants.defaultClaudeModel;

  String _googleModel = AppConstants.defaultGoogleModel;
  String _googleEmbeddingModel = AppConstants.defaultGoogleEmbeddingModel;

  // Dynamic model options fetched or candidate lists
  List<String> _currentProviderModels = AppConstants.textModels;

  // Visibility toggles for API keys
  bool _obscureDeepSeekKey = true;
  bool _obscureOpenAiKey = true;
  bool _obscureClaudeKey = true;
  bool _obscureGoogleKey = true;

  // Show Advanced URL input
  bool _showCustomHost = false;

  // Connection testing state
  bool _isTesting = false;
  bool? _connectionStatus;
  String _connectionMessage = '';
  int _pingTookMs = 0;

  // Storage Stats
  Map<String, dynamic> _storageStats = {};
  bool _isLoadingStats = true;

  @override
  void initState() {
    super.initState();
    _selectedProvider = widget.ollamaClient.provider;
    _initDefaults();
    _loadPreferences();
    _loadStats();
  }

  void _initDefaults() {
    _ollamaHostCtrl.text = AppConstants.defaultOllamaHost;
    _fastApiHostCtrl.text = AppConstants.defaultFastApiHost;
    _deepSeekHostCtrl.text = AppConstants.defaultDeepSeekHost;
    _openAiHostCtrl.text = AppConstants.defaultOpenAiHost;
    _claudeHostCtrl.text = AppConstants.defaultClaudeHost;
    _googleHostCtrl.text = AppConstants.defaultGoogleHost;
  }

  @override
  void dispose() {
    _ollamaHostCtrl.dispose();
    _fastApiHostCtrl.dispose();
    _deepSeekKeyCtrl.dispose();
    _deepSeekHostCtrl.dispose();
    _openAiKeyCtrl.dispose();
    _openAiHostCtrl.dispose();
    _claudeKeyCtrl.dispose();
    _claudeHostCtrl.dispose();
    _googleKeyCtrl.dispose();
    _googleHostCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final savedProvId = prefs.getString(AppConstants.prefAiProvider);
    final prov = savedProvId != null ? AiProvider.fromId(savedProvId) : widget.ollamaClient.provider;

    setState(() {
      _selectedProvider = prov;

      // Ollama
      _ollamaHostCtrl.text = prefs.getString(AppConstants.prefOllamaHost) ?? AppConstants.defaultOllamaHost;
      _ollamaTextModel = prefs.getString(AppConstants.prefTextModel) ?? AppConstants.defaultTextTagModel;
      _ollamaEmbeddingModel = prefs.getString(AppConstants.prefEmbeddingModel) ?? AppConstants.defaultEmbeddingModel;

      // FastAPI
      _fastApiHostCtrl.text = prefs.getString(AppConstants.prefFastApiHost) ?? AppConstants.defaultFastApiHost;

      // DeepSeek
      _deepSeekKeyCtrl.text = prefs.getString(AppConstants.prefDeepSeekApiKey) ?? '';
      _deepSeekHostCtrl.text = prefs.getString(AppConstants.prefDeepSeekHost) ?? AppConstants.defaultDeepSeekHost;
      _deepSeekModel = prefs.getString(AppConstants.prefDeepSeekModel) ?? AppConstants.defaultDeepSeekModel;

      // OpenAI
      _openAiKeyCtrl.text = prefs.getString(AppConstants.prefOpenAiApiKey) ?? '';
      _openAiHostCtrl.text = prefs.getString(AppConstants.prefOpenAiHost) ?? AppConstants.defaultOpenAiHost;
      _openAiModel = prefs.getString(AppConstants.prefOpenAiModel) ?? AppConstants.defaultOpenAiModel;
      _openAiEmbeddingModel = prefs.getString(AppConstants.prefOpenAiEmbeddingModel) ?? AppConstants.defaultOpenAiEmbeddingModel;

      // Claude
      _claudeKeyCtrl.text = prefs.getString(AppConstants.prefClaudeApiKey) ?? '';
      _claudeHostCtrl.text = prefs.getString(AppConstants.prefClaudeHost) ?? AppConstants.defaultClaudeHost;
      _claudeModel = prefs.getString(AppConstants.prefClaudeModel) ?? AppConstants.defaultClaudeModel;

      // Google
      _googleKeyCtrl.text = prefs.getString(AppConstants.prefGoogleApiKey) ?? '';
      _googleHostCtrl.text = prefs.getString(AppConstants.prefGoogleHost) ?? AppConstants.defaultGoogleHost;
      _googleModel = prefs.getString(AppConstants.prefGoogleModel) ?? AppConstants.defaultGoogleModel;
      _googleEmbeddingModel = prefs.getString(AppConstants.prefGoogleEmbeddingModel) ?? AppConstants.defaultGoogleEmbeddingModel;

      _updateAvailableModelsList();
    });
  }

  void _updateAvailableModelsList() {
    switch (_selectedProvider) {
      case AiProvider.ollama:
        _currentProviderModels = AppConstants.textModels;
        break;
      case AiProvider.fastapi:
        _currentProviderModels = AppConstants.textModels;
        break;
      case AiProvider.deepseek:
        _currentProviderModels = AppConstants.deepSeekModels;
        break;
      case AiProvider.openai:
        _currentProviderModels = AppConstants.openAiModels;
        break;
      case AiProvider.claude:
        _currentProviderModels = AppConstants.claudeModels;
        break;
      case AiProvider.google:
        _currentProviderModels = AppConstants.googleModels;
        break;
    }
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(AppConstants.prefAiProvider, _selectedProvider.id);

    // Ollama
    await prefs.setString(AppConstants.prefOllamaHost, _ollamaHostCtrl.text.trim());
    await prefs.setString(AppConstants.prefTextModel, _ollamaTextModel);
    await prefs.setString(AppConstants.prefEmbeddingModel, _ollamaEmbeddingModel);

    // FastAPI
    await prefs.setString(AppConstants.prefFastApiHost, _fastApiHostCtrl.text.trim());
    await prefs.setBool(AppConstants.prefFastApiEnabled, _selectedProvider == AiProvider.fastapi);

    // DeepSeek
    await prefs.setString(AppConstants.prefDeepSeekApiKey, _deepSeekKeyCtrl.text.trim());
    await prefs.setString(AppConstants.prefDeepSeekHost, _deepSeekHostCtrl.text.trim());
    await prefs.setString(AppConstants.prefDeepSeekModel, _deepSeekModel);

    // OpenAI
    await prefs.setString(AppConstants.prefOpenAiApiKey, _openAiKeyCtrl.text.trim());
    await prefs.setString(AppConstants.prefOpenAiHost, _openAiHostCtrl.text.trim());
    await prefs.setString(AppConstants.prefOpenAiModel, _openAiModel);
    await prefs.setString(AppConstants.prefOpenAiEmbeddingModel, _openAiEmbeddingModel);

    // Claude
    await prefs.setString(AppConstants.prefClaudeApiKey, _claudeKeyCtrl.text.trim());
    await prefs.setString(AppConstants.prefClaudeHost, _claudeHostCtrl.text.trim());
    await prefs.setString(AppConstants.prefClaudeModel, _claudeModel);

    // Google
    await prefs.setString(AppConstants.prefGoogleApiKey, _googleKeyCtrl.text.trim());
    await prefs.setString(AppConstants.prefGoogleHost, _googleHostCtrl.text.trim());
    await prefs.setString(AppConstants.prefGoogleModel, _googleModel);
    await prefs.setString(AppConstants.prefGoogleEmbeddingModel, _googleEmbeddingModel);

    // Update active client properties
    widget.ollamaClient.provider = _selectedProvider;
    widget.ollamaClient.isFastApi = (_selectedProvider == AiProvider.fastapi);

    switch (_selectedProvider) {
      case AiProvider.ollama:
        widget.ollamaClient.host = _ollamaHostCtrl.text.trim();
        widget.ollamaClient.textModel = _ollamaTextModel;
        widget.ollamaClient.embeddingModel = _ollamaEmbeddingModel;
        widget.ollamaClient.apiKey = '';
        break;
      case AiProvider.fastapi:
        widget.ollamaClient.host = _fastApiHostCtrl.text.trim();
        widget.ollamaClient.textModel = _ollamaTextModel;
        widget.ollamaClient.embeddingModel = _ollamaEmbeddingModel;
        widget.ollamaClient.apiKey = '';
        break;
      case AiProvider.deepseek:
        widget.ollamaClient.host = _deepSeekHostCtrl.text.trim();
        widget.ollamaClient.textModel = _deepSeekModel;
        widget.ollamaClient.embeddingModel = '';
        widget.ollamaClient.apiKey = _deepSeekKeyCtrl.text.trim();
        break;
      case AiProvider.openai:
        widget.ollamaClient.host = _openAiHostCtrl.text.trim();
        widget.ollamaClient.textModel = _openAiModel;
        widget.ollamaClient.embeddingModel = _openAiEmbeddingModel;
        widget.ollamaClient.apiKey = _openAiKeyCtrl.text.trim();
        break;
      case AiProvider.claude:
        widget.ollamaClient.host = _claudeHostCtrl.text.trim();
        widget.ollamaClient.textModel = _claudeModel;
        widget.ollamaClient.embeddingModel = '';
        widget.ollamaClient.apiKey = _claudeKeyCtrl.text.trim();
        break;
      case AiProvider.google:
        widget.ollamaClient.host = _googleHostCtrl.text.trim();
        widget.ollamaClient.textModel = _googleModel;
        widget.ollamaClient.embeddingModel = _googleEmbeddingModel;
        widget.ollamaClient.apiKey = _googleKeyCtrl.text.trim();
        break;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已成功儲存 ${_selectedProvider.displayName} 設定'),
          backgroundColor: Colors.teal,
        ),
      );
    }
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _connectionStatus = null;
      _connectionMessage = '';
    });

    String targetHost = '';
    String targetKey = '';

    switch (_selectedProvider) {
      case AiProvider.ollama:
        targetHost = _ollamaHostCtrl.text.trim();
        break;
      case AiProvider.fastapi:
        targetHost = _fastApiHostCtrl.text.trim();
        break;
      case AiProvider.deepseek:
        targetHost = _deepSeekHostCtrl.text.trim();
        targetKey = _deepSeekKeyCtrl.text.trim();
        break;
      case AiProvider.openai:
        targetHost = _openAiHostCtrl.text.trim();
        targetKey = _openAiKeyCtrl.text.trim();
        break;
      case AiProvider.claude:
        targetHost = _claudeHostCtrl.text.trim();
        targetKey = _claudeKeyCtrl.text.trim();
        break;
      case AiProvider.google:
        targetHost = _googleHostCtrl.text.trim();
        targetKey = _googleKeyCtrl.text.trim();
        break;
    }

    if ((_selectedProvider == AiProvider.deepseek ||
            _selectedProvider == AiProvider.openai ||
            _selectedProvider == AiProvider.claude ||
            _selectedProvider == AiProvider.google) &&
        targetKey.isEmpty) {
      setState(() {
        _isTesting = false;
        _connectionStatus = false;
        _connectionMessage = '請先填寫 API Key';
      });
      return;
    }

    final sw = Stopwatch()..start();
    final ok = await widget.ollamaClient.testConnection(
      customHost: targetHost,
      customApiKey: targetKey,
      targetProvider: _selectedProvider,
    );
    sw.stop();

    if (ok) {
      final models = await widget.ollamaClient.listAvailableModels(
        customHost: targetHost,
        customApiKey: targetKey,
        targetProvider: _selectedProvider,
      );
      if (mounted && models.isNotEmpty) {
        setState(() => _currentProviderModels = models);
      }
    }

    if (mounted) {
      setState(() {
        _isTesting = false;
        _connectionStatus = ok;
        _pingTookMs = sw.elapsedMilliseconds;
        _connectionMessage = ok ? '連線成功 (${_pingTookMs}ms)' : '連線失敗，請檢查金鑰或網路位址';
      });
    }
  }

  Future<void> _loadStats() async {
    final stats = await widget.repository.getStorageStats();
    if (mounted) {
      setState(() {
        _storageStats = stats;
        _isLoadingStats = false;
      });
    }
  }

  Future<void> _exportBackup() async {
    final backup = await widget.repository.exportBackup();
    if (mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('資料庫備份導出'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('備份資料已成功產生（JSON 格式）：'),
              const SizedBox(height: 10),
              Container(
                height: 150,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(6)),
                child: SingleChildScrollView(
                  child: Text(backup, style: const TextStyle(fontSize: 10, fontFamily: 'monospace')),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('關閉')),
          ],
        ),
      );
    }
  }

  Future<void> _clearAllData() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('警告：清除全部資料庫'),
        content: const Text('確定要清除 KoreDB 中所有文獻、標籤與向量索引嗎？此操作不可逆！'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('確認清除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await widget.repository.clearAll();
      _loadStats();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已成功清除所有資料庫內容')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('系統設定', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: '儲存設定',
            onPressed: _saveSettings,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Section: AI Provider Selection & Settings
          _buildAiProviderCard(),

          const SizedBox(height: 14),

          // Section: KoreDB Storage & Backup
          _buildKoreDbStorageCard(),

          const SizedBox(height: 14),

          // Section: Interface & Preferences
          _buildPreferencesCard(),
        ],
      ),
    );
  }

  Widget _buildAiProviderCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.smart_toy, color: Colors.indigo),
                const SizedBox(width: 8),
                const Text('AI 推理服務設定', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 14),

            // Provider Dropdown Selector
            InputDecorator(
              decoration: const InputDecoration(
                labelText: '選擇 AI 服務提供商 (Provider)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.account_tree_outlined),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<AiProvider>(
                  value: _selectedProvider,
                  isExpanded: true,
                  items: AiProvider.values.map((prov) {
                    return DropdownMenuItem<AiProvider>(
                      value: prov,
                      child: Row(
                        children: [
                          _buildProviderIcon(prov),
                          const SizedBox(width: 10),
                          Text(prov.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (prov) {
                    if (prov != null) {
                      setState(() {
                        _selectedProvider = prov;
                        _connectionStatus = null;
                        _connectionMessage = '';
                        _updateAvailableModelsList();
                      });
                    }
                  },
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Dynamic Provider-specific fields
            ..._buildProviderFields(),

            const SizedBox(height: 16),

            // Connection Test Button & Status
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _isTesting ? null : _testConnection,
                  icon: _isTesting
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.network_check),
                  label: const Text('連線測試'),
                ),
                const SizedBox(width: 12),
                if (_connectionStatus != null)
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: (_connectionStatus == true ? Colors.green : Colors.red).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _connectionStatus == true ? Icons.check_circle : Icons.cancel,
                            size: 16,
                            color: _connectionStatus == true ? Colors.green : Colors.red,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _connectionMessage,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: _connectionStatus == true ? Colors.green : Colors.red,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProviderIcon(AiProvider prov) {
    switch (prov) {
      case AiProvider.ollama:
        return const Icon(Icons.computer, color: Colors.blue, size: 20);
      case AiProvider.fastapi:
        return const Icon(Icons.bolt, color: Colors.orange, size: 20);
      case AiProvider.deepseek:
        return const Icon(Icons.water, color: Colors.lightBlue, size: 20);
      case AiProvider.openai:
        return const Icon(Icons.auto_awesome, color: Colors.teal, size: 20);
      case AiProvider.claude:
        return const Icon(Icons.psychology, color: Colors.deepPurple, size: 20);
      case AiProvider.google:
        return const Icon(Icons.cloud, color: Colors.redAccent, size: 20);
    }
  }

  List<Widget> _buildProviderFields() {
    switch (_selectedProvider) {
      case AiProvider.ollama:
        return [
          TextField(
            controller: _ollamaHostCtrl,
            decoration: const InputDecoration(
              labelText: '區域網 Ollama 服務位址',
              hintText: 'http://192.168.1.100:11434',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.lan),
              helperText: '確保手機與伺服器處於同一 Wi-Fi 或可互通之區網',
            ),
          ),
          const SizedBox(height: 14),
          _buildModelDropdown(
            label: '文字標籤生成模型 (Text Model)',
            value: _ollamaTextModel,
            candidates: _currentProviderModels,
            onChanged: (val) => setState(() => _ollamaTextModel = val),
          ),
          const SizedBox(height: 14),
          _buildModelDropdown(
            label: '向量嵌入模型 (Embedding Model)',
            value: _ollamaEmbeddingModel,
            candidates: AppConstants.embeddingModels,
            onChanged: (val) => setState(() => _ollamaEmbeddingModel = val),
          ),
        ];

      case AiProvider.fastapi:
        return [
          TextField(
            controller: _fastApiHostCtrl,
            decoration: const InputDecoration(
              labelText: 'FastAPI 中間層位址',
              hintText: 'http://192.168.1.100:8000',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.api),
              helperText: '支援 /generate-tags, /embed, /models 等自訂轉發介面',
            ),
          ),
          const SizedBox(height: 14),
          _buildModelDropdown(
            label: '後端轉發模型名稱',
            value: _ollamaTextModel,
            candidates: _currentProviderModels,
            onChanged: (val) => setState(() => _ollamaTextModel = val),
          ),
        ];

      case AiProvider.deepseek:
        return [
          TextField(
            controller: _deepSeekKeyCtrl,
            obscureText: _obscureDeepSeekKey,
            decoration: InputDecoration(
              labelText: 'DeepSeek API Key',
              hintText: 'sk-...',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.key),
              suffixIcon: IconButton(
                icon: Icon(_obscureDeepSeekKey ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscureDeepSeekKey = !_obscureDeepSeekKey),
              ),
              helperText: '請至 platform.deepseek.com 申請獲取 API 金鑰',
            ),
          ),
          const SizedBox(height: 14),
          _buildModelDropdown(
            label: 'DeepSeek 模型選用',
            value: _deepSeekModel,
            candidates: _currentProviderModels,
            onChanged: (val) => setState(() => _deepSeekModel = val),
          ),
          const SizedBox(height: 10),
          _buildAdvancedHostTile(
            controller: _deepSeekHostCtrl,
            label: 'DeepSeek 端點位址 (預設 https://api.deepseek.com)',
          ),
          const SizedBox(height: 4),
          _buildEmbeddingNotice('DeepSeek 提供極致性價比標籤抽取；向量索引由本地 KoreDB BM25 關鍵字與反向標籤輔助。'),
        ];

      case AiProvider.openai:
        return [
          TextField(
            controller: _openAiKeyCtrl,
            obscureText: _obscureOpenAiKey,
            decoration: InputDecoration(
              labelText: 'OpenAI API Key',
              hintText: 'sk-...',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.key),
              suffixIcon: IconButton(
                icon: Icon(_obscureOpenAiKey ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscureOpenAiKey = !_obscureOpenAiKey),
              ),
              helperText: '請至 platform.openai.com 申請獲取 API 金鑰',
            ),
          ),
          const SizedBox(height: 14),
          _buildModelDropdown(
            label: 'OpenAI 標籤生成模型',
            value: _openAiModel,
            candidates: _currentProviderModels,
            onChanged: (val) => setState(() => _openAiModel = val),
          ),
          const SizedBox(height: 14),
          _buildModelDropdown(
            label: 'OpenAI 向量嵌入模型 (Embeddings)',
            value: _openAiEmbeddingModel,
            candidates: AppConstants.openAiEmbeddingModels,
            onChanged: (val) => setState(() => _openAiEmbeddingModel = val),
          ),
          const SizedBox(height: 10),
          _buildAdvancedHostTile(
            controller: _openAiHostCtrl,
            label: 'OpenAI API 位址 (支援自訂反向代理)',
          ),
        ];

      case AiProvider.claude:
        return [
          TextField(
            controller: _claudeKeyCtrl,
            obscureText: _obscureClaudeKey,
            decoration: InputDecoration(
              labelText: 'Anthropic Claude API Key',
              hintText: 'sk-ant-...',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.key),
              suffixIcon: IconButton(
                icon: Icon(_obscureClaudeKey ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscureClaudeKey = !_obscureClaudeKey),
              ),
              helperText: '請至 console.anthropic.com 申請獲取 API 金鑰',
            ),
          ),
          const SizedBox(height: 14),
          _buildModelDropdown(
            label: 'Claude 標籤生成模型',
            value: _claudeModel,
            candidates: _currentProviderModels,
            onChanged: (val) => setState(() => _claudeModel = val),
          ),
          const SizedBox(height: 10),
          _buildAdvancedHostTile(
            controller: _claudeHostCtrl,
            label: 'Claude API 端點位址 (預設 https://api.anthropic.com/v1)',
          ),
          const SizedBox(height: 4),
          _buildEmbeddingNotice('Claude 具備頂尖文獻理解與多維特徵歸納；向量索引由本地 KoreDB 高性能反向倒排索引處理。'),
        ];

      case AiProvider.google:
        return [
          TextField(
            controller: _googleKeyCtrl,
            obscureText: _obscureGoogleKey,
            decoration: InputDecoration(
              labelText: 'Google Gemini API Key',
              hintText: 'AIzaSy...',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.key),
              suffixIcon: IconButton(
                icon: Icon(_obscureGoogleKey ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscureGoogleKey = !_obscureGoogleKey),
              ),
              helperText: '請至 aistudio.google.com 免費或付費取得 Gemini API 金鑰',
            ),
          ),
          const SizedBox(height: 14),
          _buildModelDropdown(
            label: 'Gemini 標籤生成模型',
            value: _googleModel,
            candidates: _currentProviderModels,
            onChanged: (val) => setState(() => _googleModel = val),
          ),
          const SizedBox(height: 14),
          _buildModelDropdown(
            label: 'Gemini 向量嵌入模型 (Embeddings)',
            value: _googleEmbeddingModel,
            candidates: AppConstants.googleEmbeddingModels,
            onChanged: (val) => setState(() => _googleEmbeddingModel = val),
          ),
          const SizedBox(height: 10),
          _buildAdvancedHostTile(
            controller: _googleHostCtrl,
            label: 'Google Gemini 端點位址',
          ),
        ];
    }
  }

  Widget _buildModelDropdown({
    required String label,
    required String value,
    required List<String> candidates,
    required ValueChanged<String> onChanged,
  }) {
    final items = candidates.contains(value) ? candidates : [value, ...candidates];

    return DropdownButtonFormField<String>(
      key: ValueKey('$label-$value'),
      initialValue: items.contains(value) ? value : items.first,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: items.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
      onChanged: (val) {
        if (val != null) onChanged(val);
      },
    );
  }

  Widget _buildAdvancedHostTile({
    required TextEditingController controller,
    required String label,
  }) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        dense: true,
        tilePadding: EdgeInsets.zero,
        title: Text(
          _showCustomHost ? '自訂 API 端點 URL (已展開)' : '自訂 API 端點 URL (選填代理)',
          style: const TextStyle(fontSize: 13, color: Colors.blueGrey),
        ),
        onExpansionChanged: (expanded) => setState(() => _showCustomHost = expanded),
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: label,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.link),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmbeddingNotice(String message) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 18, color: Colors.blue),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: const TextStyle(fontSize: 12, color: Colors.black87)),
          ),
        ],
      ),
    );
  }

  Widget _buildKoreDbStorageCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.storage, color: Colors.teal),
                const SizedBox(width: 8),
                const Text('KoreDB 本地存儲與備份', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 12),

            if (_isLoadingStats)
              const LinearProgressIndicator()
            else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStorageStat('文獻數', '${_storageStats['documentCount'] ?? 0}'),
                  _buildStorageStat('頁數', '${_storageStats['pageCount'] ?? 0}'),
                  _buildStorageStat('標籤數', '${_storageStats['tagCount'] ?? 0}'),
                  _buildStorageStat('向量數', '${_storageStats['vectorCount'] ?? 0}'),
                ],
              ),
            ],

            const SizedBox(height: 16),
            const Divider(),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.download),
                    label: const Text('匯出備份 (JSON)'),
                    onPressed: _exportBackup,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                    icon: const Icon(Icons.delete_forever),
                    label: const Text('清空資料庫'),
                    onPressed: _clearAllData,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreferencesCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('介面與隱私偏好', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('深色模式 (Dark Theme)'),
              value: widget.isDarkMode,
              onChanged: (val) {
                widget.onThemeChanged(val);
              },
            ),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.security, color: Colors.green),
              title: Text('本機隱私保護'),
              subtitle: Text('文獻內容與反向標籤索引均存於本地 KoreDB 嵌入式引擎，確保資產安全。'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStorageStat(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}
