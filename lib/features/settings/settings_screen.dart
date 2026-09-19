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
  final TextEditingController _hostCtrl = TextEditingController();
  final TextEditingController _fastApiHostCtrl = TextEditingController();

  bool _isFastApi = false;
  String _selectedTextModel = AppConstants.defaultTextTagModel;
  String _selectedEmbeddingModel = AppConstants.defaultEmbeddingModel;
  List<String> _availableModels = AppConstants.textModels;

  bool _isTesting = false;
  bool? _connectionStatus;
  int _pingTookMs = 0;

  Map<String, dynamic> _storageStats = {};
  bool _isLoadingStats = true;

  @override
  void initState() {
    super.initState();
    _hostCtrl.text = widget.ollamaClient.host;
    _selectedTextModel = widget.ollamaClient.textModel;
    _selectedEmbeddingModel = widget.ollamaClient.embeddingModel;
    _isFastApi = widget.ollamaClient.isFastApi;
    _loadPreferences();
    _loadStats();
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _fastApiHostCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _hostCtrl.text = prefs.getString(AppConstants.prefOllamaHost) ?? widget.ollamaClient.host;
      _selectedTextModel = prefs.getString(AppConstants.prefTextModel) ?? widget.ollamaClient.textModel;
      _selectedEmbeddingModel = prefs.getString(AppConstants.prefEmbeddingModel) ?? widget.ollamaClient.embeddingModel;
      _isFastApi = prefs.getBool(AppConstants.prefFastApiEnabled) ?? false;
      _fastApiHostCtrl.text = prefs.getString(AppConstants.prefFastApiHost) ?? 'http://192.168.1.100:8000';
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.prefOllamaHost, _hostCtrl.text.trim());
    await prefs.setString(AppConstants.prefTextModel, _selectedTextModel);
    await prefs.setString(AppConstants.prefEmbeddingModel, _selectedEmbeddingModel);
    await prefs.setBool(AppConstants.prefFastApiEnabled, _isFastApi);
    await prefs.setString(AppConstants.prefFastApiHost, _fastApiHostCtrl.text.trim());

    widget.ollamaClient.host = _isFastApi ? _fastApiHostCtrl.text.trim() : _hostCtrl.text.trim();
    widget.ollamaClient.textModel = _selectedTextModel;
    widget.ollamaClient.embeddingModel = _selectedEmbeddingModel;
    widget.ollamaClient.isFastApi = _isFastApi;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('設定已成功儲存')),
      );
    }
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _connectionStatus = null;
    });

    final sw = Stopwatch()..start();
    final target = _isFastApi ? _fastApiHostCtrl.text.trim() : _hostCtrl.text.trim();
    final ok = await widget.ollamaClient.testConnection(customHost: target);
    sw.stop();

    if (ok) {
      final models = await widget.ollamaClient.listAvailableModels(customHost: target);
      if (mounted && models.isNotEmpty) {
        setState(() => _availableModels = models);
      }
    }

    if (mounted) {
      setState(() {
        _isTesting = false;
        _connectionStatus = ok;
        _pingTookMs = sw.elapsedMilliseconds;
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
          // Section: Ollama Connection
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.hub, color: Colors.blue),
                      const SizedBox(width: 8),
                      const Text('AI 推理服務設定', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Toggle between direct Ollama vs FastAPI
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('使用 FastAPI 中間層'),
                    subtitle: const Text('推薦架構：手機 → FastAPI (/generate-tags, /embed) → Ollama'),
                    value: _isFastApi,
                    onChanged: (val) {
                      setState(() => _isFastApi = val);
                    },
                  ),

                  const SizedBox(height: 8),

                  if (!_isFastApi) ...[
                    TextField(
                      controller: _hostCtrl,
                      decoration: const InputDecoration(
                        labelText: '區域網 Ollama 位址',
                        hintText: 'http://192.168.1.100:11434',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.computer),
                      ),
                    ),
                  ] else ...[
                    TextField(
                      controller: _fastApiHostCtrl,
                      decoration: const InputDecoration(
                        labelText: 'FastAPI 中間層位址',
                        hintText: 'http://192.168.1.100:8000',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.api),
                      ),
                    ),
                  ],

                  const SizedBox(height: 12),

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
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                              Text(
                                _connectionStatus == true ? '連線成功 (${_pingTookMs}ms)' : '連線失敗',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: _connectionStatus == true ? Colors.green : Colors.red,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 14),

          // Section: Model Choices
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.psychology, color: Colors.purple),
                      const SizedBox(width: 8),
                      const Text('AI 模型選用', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Text Tagging Model
                  DropdownButtonFormField<String>(
                    initialValue: _availableModels.contains(_selectedTextModel) ? _selectedTextModel : _availableModels.first,
                    decoration: const InputDecoration(
                      labelText: '文字標籤生成模型',
                      helperText: '推薦: qwen2.5:3b (中文多維標籤結構性最佳)',
                      border: OutlineInputBorder(),
                    ),
                    items: _availableModels.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedTextModel = val);
                    },
                  ),

                  const SizedBox(height: 14),

                  // Embedding Model
                  DropdownButtonFormField<String>(
                    initialValue: AppConstants.embeddingModels.contains(_selectedEmbeddingModel)
                        ? _selectedEmbeddingModel
                        : AppConstants.embeddingModels.first,
                    decoration: const InputDecoration(
                      labelText: '向量嵌入模型 (Semantic Embeddings)',
                      helperText: '推薦: nomic-embed-text (高效高品質通用向量)',
                      border: OutlineInputBorder(),
                    ),
                    items: AppConstants.embeddingModels.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedEmbeddingModel = val);
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 14),

          // Section: KoreDB Storage & Backup
          Card(
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
          ),

          const SizedBox(height: 14),

          // Section: Interface & Preferences
          Card(
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
                    subtitle: Text('文獻內容與標籤均存於本地 KoreDB，不傳輸至任何雲端伺服器。'),
                  ),
                ],
              ),
            ),
          ),
        ],
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
