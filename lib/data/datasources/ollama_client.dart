import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:smart_doc_search/core/constants/app_constants.dart';
import 'package:smart_doc_search/core/utils/text_normalizer.dart';
import 'package:smart_doc_search/data/models/document_model.dart';

class OllamaClient {
  final Dio _dio;
  String host;
  String textModel;
  String embeddingModel;
  bool isFastApi;

  OllamaClient({
    Dio? dio,
    this.host = AppConstants.defaultOllamaHost,
    this.textModel = AppConstants.defaultTextTagModel,
    this.embeddingModel = AppConstants.defaultEmbeddingModel,
    this.isFastApi = false,
  }) : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 60),
              sendTimeout: const Duration(seconds: 30),
            ));

  /// Tests connectivity to Ollama or FastAPI server.
  Future<bool> testConnection({String? customHost}) async {
    final targetHost = (customHost ?? host).replaceAll(RegExp(r'/+$'), '');
    try {
      if (isFastApi) {
        final res = await _dio.get('$targetHost/health');
        return res.statusCode == 200;
      } else {
        final res = await _dio.get('$targetHost/api/tags');
        return res.statusCode == 200;
      }
    } catch (e) {
      debugPrint('Connection test failed for $targetHost: $e');
      return false;
    }
  }

  /// Lists available models on server
  Future<List<String>> listAvailableModels({String? customHost}) async {
    final targetHost = (customHost ?? host).replaceAll(RegExp(r'/+$'), '');
    try {
      if (isFastApi) {
        final res = await _dio.get('$targetHost/models');
        if (res.data is Map && res.data['models'] is List) {
          return (res.data['models'] as List).map((e) => e.toString()).toList();
        }
      } else {
        final res = await _dio.get('$targetHost/api/tags');
        if (res.data is Map && res.data['models'] is List) {
          final list = res.data['models'] as List;
          return list.map((m) => (m['name'] ?? m['model'] ?? '').toString()).where((s) => s.isNotEmpty).toList();
        }
      }
    } catch (e) {
      debugPrint('Failed to list models: $e');
    }
    return AppConstants.textModels;
  }

  /// Generates tags for document content using Ollama `/api/chat` or FastAPI `/generate-tags`
  Future<List<TagItem>> generateTags({
    required String text,
    String? imageBase64,
    List<String>? dimensions,
    String? model,
    int maxRetries = 3,
  }) async {
    final targetModel = model ?? textModel;
    final dims = dimensions ?? AppConstants.defaultTagDimensions;
    final cleanHost = host.replaceAll(RegExp(r'/+$'), '');

    if (isFastApi) {
      return _generateTagsViaFastApi(cleanHost, targetModel, text, imageBase64, dims);
    } else {
      return _generateTagsViaOllamaWithRetry(cleanHost, targetModel, text, dims, maxRetries);
    }
  }

  Future<List<TagItem>> _generateTagsViaFastApi(
    String targetHost,
    String model,
    String text,
    String? imageBase64,
    List<String> dims,
  ) async {
    try {
      final res = await _dio.post(
        '$targetHost/generate-tags',
        data: {
          'text': text,
          'image_base64': ?imageBase64,
          'dimensions': dims,
          'model': model,
        },
      );
      if (res.statusCode == 200 && res.data is Map) {
        final List rawTags = res.data['tags'] ?? [];
        return _parseTagItems(rawTags, source: imageBase64 != null ? 'ai_image' : 'ai_text');
      }
    } catch (e) {
      debugPrint('FastAPI generate-tags error: $e');
      rethrow;
    }
    return [];
  }

  Future<List<TagItem>> _generateTagsViaOllamaWithRetry(
    String targetHost,
    String model,
    String text,
    List<String> dims,
    int maxRetries,
  ) async {
    int attempts = 0;
    String promptText = _buildPrompt(text, dims, attempt: attempts);

    while (attempts < maxRetries) {
      attempts++;
      try {
        final payload = {
          'model': model,
          'messages': [
            {
              'role': 'user',
              'content': promptText,
            }
          ],
          'format': 'json',
          'stream': false,
        };

        final response = await _dio.post(
          '$targetHost/api/chat',
          data: payload,
          options: Options(headers: {'Content-Type': 'application/json'}),
        );

        if (response.statusCode == 200 && response.data != null) {
          final content = response.data['message']?['content'] ?? '';
          final tags = _parseJsonContent(content);
          if (tags.isNotEmpty) {
            return tags;
          }
        }
      } catch (e) {
        debugPrint('Ollama tag generation attempt $attempts failed: $e');
        if (attempts >= maxRetries) rethrow;
      }

      // Slightly refine prompt on retry
      promptText = _buildPrompt(text, dims, attempt: attempts);
      await Future.delayed(Duration(milliseconds: 500 * attempts));
    }

    return [];
  }

  String _buildPrompt(String text, List<String> dims, {int attempt = 0}) {
    final truncatedText = text.length > 3000 ? text.substring(0, 3000) : text;
    final dimListStr = dims.join('、');

    return '''你是一個精準的文獻分析助手。請閱讀下方文獻內容，擷取結構化多維標籤。
標籤維度包含：$dimListStr。
請嚴格以 JSON 格式回應，不輸出多餘文字：
{
  "tags": [
    {"name": "標籤名稱", "category": "維度", "confidence": 0.95}
  ]
}
文獻內容：
---
$truncatedText
---
''';
  }

  List<TagItem> _parseJsonContent(String content) {
    try {
      var cleaned = content.trim();
      // Remove markdown ```json ``` wraps if any
      if (cleaned.startsWith('```')) {
        cleaned = cleaned.replaceAll(RegExp(r'^```(json)?|```$', multiLine: true), '').trim();
      }

      final parsed = json.decode(cleaned);
      if (parsed is Map && parsed['tags'] is List) {
        return _parseTagItems(parsed['tags'] as List, source: 'ai_text');
      } else if (parsed is List) {
        return _parseTagItems(parsed, source: 'ai_text');
      }
    } catch (e) {
      debugPrint('Error parsing JSON from Ollama response: $e, content: $content');
    }
    return [];
  }

  List<TagItem> _parseTagItems(List rawList, {String source = 'ai_text'}) {
    final results = <TagItem>[];
    final seen = <String>{};

    for (final item in rawList) {
      if (item is Map) {
        final rawName = (item['name'] ?? item['tag'] ?? '').toString();
        final normalizedName = TextNormalizer.normalizeTag(rawName);
        if (normalizedName.isEmpty || seen.contains(normalizedName.toLowerCase())) continue;
        seen.add(normalizedName.toLowerCase());

        final category = (item['category'] ?? item['dimension'] ?? '主題').toString();
        final conf = (item['confidence'] is num) ? (item['confidence'] as num).toDouble() : 0.9;

        results.add(TagItem(
          id: 'tag_${DateTime.now().microsecondsSinceEpoch}_${results.length}',
          name: normalizedName,
          category: category,
          confidence: conf,
          source: source,
          verified: false,
        ));
      }
    }
    return results;
  }

  /// Generates vector embeddings for a given text using Ollama `/api/embeddings` or FastAPI `/embed`
  Future<List<double>> embed({
    required String text,
    String? model,
  }) async {
    final targetModel = model ?? embeddingModel;
    final cleanHost = host.replaceAll(RegExp(r'/+$'), '');

    if (isFastApi) {
      try {
        final res = await _dio.post(
          '$cleanHost/embed',
          data: {'text': text, 'model': targetModel},
        );
        if (res.statusCode == 200 && res.data is Map && res.data['embedding'] is List) {
          return (res.data['embedding'] as List).map((e) => (e as num).toDouble()).toList();
        }
      } catch (e) {
        debugPrint('FastAPI embed error: $e');
        return [];
      }
    } else {
      try {
        final res = await _dio.post(
          '$cleanHost/api/embeddings',
          data: {
            'model': targetModel,
            'prompt': text.length > 2000 ? text.substring(0, 2000) : text,
          },
        );
        if (res.statusCode == 200 && res.data is Map && res.data['embedding'] is List) {
          return (res.data['embedding'] as List).map((e) => (e as num).toDouble()).toList();
        }
      } catch (e) {
        debugPrint('Ollama embeddings API error: $e');
      }
    }
    return [];
  }
}
