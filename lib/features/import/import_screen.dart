import 'dart:async';
import 'package:flutter/material.dart';
import 'package:smart_doc_search/core/theme/app_theme.dart';
import 'package:smart_doc_search/features/import/import_service.dart';

class ImportScreen extends StatefulWidget {
  final ImportService importService;
  final VoidCallback onImportSuccess;

  const ImportScreen({
    super.key,
    required this.importService,
    required this.onImportSuccess,
  });

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  StreamSubscription<ImportProgress>? _subscription;
  final List<ImportProgress> _history = [];
  bool _isImporting = false;
  int _totalSelected = 0;
  int _completedCount = 0;

  @override
  void initState() {
    super.initState();
    _subscription = widget.importService.progressStream.listen((prog) {
      if (!mounted) return;
      setState(() {
        final existingIdx = _history.indexWhere((p) => p.fileName == prog.fileName);
        if (existingIdx >= 0) {
          _history[existingIdx] = prog;
        } else {
          _history.insert(0, prog);
        }

        if (prog.stage == ImportStage.completed || prog.stage == ImportStage.error) {
          _completedCount++;
        }
      });
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _startFilePicker() async {
    final paths = await widget.importService.pickDocumentFiles();
    if (paths.isEmpty) return;

    setState(() {
      _isImporting = true;
      _totalSelected = paths.length;
      _completedCount = 0;
    });

    try {
      await widget.importService.importBatch(paths);
      widget.onImportSuccess();
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('匯入文獻', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (_history.isNotEmpty && !_isImporting)
            IconButton(
              icon: const Icon(Icons.clear_all),
              tooltip: '清空列表',
              onPressed: () => setState(() => _history.clear()),
            ),
        ],
      ),
      body: Column(
        children: [
          // Picker Card
          Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3), width: 1.5),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _isImporting ? null : _startFilePicker,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.cloud_upload_outlined,
                          size: 40,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        '點擊選取檔案進行匯入',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '支援多選批次匯入 • 自動 SHA-256 查重',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        children: [
                          _buildFormatChip('PDF (.pdf)', Colors.red),
                          _buildFormatChip('圖片 (.png, .jpg, .webp)', Colors.blue),
                          _buildFormatChip('PPT (.ppt, .pptx)', Colors.orange),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Active import status banner
          if (_isImporting)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '正在批次處理中 ($_completedCount / $_totalSelected)...',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 8),

          // List of imported items
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('處理歷程與進度', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                Text('${_history.length} 項', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              ],
            ),
          ),

          const SizedBox(height: 8),

          Expanded(
            child: _history.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inbox, size: 54, color: Colors.grey.shade400),
                        const SizedBox(height: 10),
                        const Text('暫無處理歷程', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    itemCount: _history.length,
                    itemBuilder: (context, index) {
                      final item = _history[index];
                      return _buildProgressItemCard(item);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressItemCard(ImportProgress item) {
    IconData icon;
    Color color;

    if (item.stage == ImportStage.completed) {
      if (item.isDuplicate) {
        icon = Icons.copy;
        color = Colors.orange;
      } else {
        icon = Icons.check_circle;
        color = Colors.green;
      }
    } else if (item.stage == ImportStage.error) {
      icon = Icons.error;
      color = Colors.red;
    } else {
      icon = Icons.autorenew;
      color = AppTheme.primaryColor;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.fileName,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${(item.progress * 100).toInt()}%',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: color),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              item.message,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            if (item.stage != ImportStage.completed && item.stage != ImportStage.error) ...[
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: item.progress,
                backgroundColor: Colors.grey.shade200,
                color: AppTheme.primaryColor,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFormatChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: color),
      ),
    );
  }
}
