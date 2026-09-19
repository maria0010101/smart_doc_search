import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:smart_doc_search/core/constants/app_constants.dart';
import 'package:smart_doc_search/core/utils/text_normalizer.dart';
import 'package:smart_doc_search/data/models/document_model.dart';

/// Unified AI service client supporting:
/// - Ollama (Local/LAN)
/// - FastAPI (Custom intermediate proxy)
/// - DeepSeek API
/// - OpenAI GPT API
/// - Anthropic Claude API
/// - Google Gemini API
class OllamaClient {
  final Dio _dio;
  AiProvider provider;
  String host;
  String textModel;
  String embeddingModel;
  String apiKey;
  bool isFastApi;

  OllamaClient({
    Dio? dio,
    this.provider = AiProvider.ollama,
    this.host = AppConstants.defaultOllamaHost,
    this.textModel = AppConstants.defaultTextTagModel,
    this.embeddingModel = AppConstants.defaultEmbeddingModel,
    this.apiKey = '',
    this.isFastApi = false,
  }) : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 60),
              sendTimeout: const Duration(seconds: 30),
            ));

  String get providerDisplayName {
    if (isFastApi) return 'FastAPI 中間層';
    return provider.displayName;
  }

  bool get isCloudProvider {
    return provider == AiProvider.deepseek ||
        provider == AiProvider.openai ||
        provider == AiProvider.claude ||
        provider == AiProvider.google;
  }

  /// Tests connectivity to selected AI provider
  Future<bool> testConnection({
    String? customHost,
    String? customApiKey,
    AiProvider? targetProvider,
  }) async {
    final prov = targetProvider ?? provider;
    final targetKey = (customApiKey ?? apiKey).trim();
    final targetHost = (customHost ?? host).replaceAll(RegExp(r'/+$'), '');

    try {
      if (isFastApi || prov == AiProvider.fastapi) {
        final res = await _dio.get('$targetHost/health');
        return res.statusCode == 200;
      }

      switch (prov) {
        case AiProvider.ollama:
          final res = await _dio.get('$targetHost/api/tags');
          return res.statusCode == 200;

        case AiProvider.deepseek:
          if (targetKey.isEmpty) return false;
          final res = await _dio.get(
            '$targetHost/models',
            options: Options(headers: {
              'Authorization': 'Bearer $targetKey',
            }),
          );
          return res.statusCode == 200;

        case AiProvider.openai:
          if (targetKey.isEmpty) return false;
          final res = await _dio.get(
            '$targetHost/models',
            options: Options(headers: {
              'Authorization': 'Bearer $targetKey',
            }),
          );
          return res.statusCode == 200;

        case AiProvider.claude:
          if (targetKey.isEmpty) return false;
          final res = await _dio.get(
            '$targetHost/models',
            options: Options(headers: {
              'x-api-key': targetKey,
              'anthropic-version': '2023-06-01',
            }),
          );
          return res.statusCode == 200;

        case AiProvider.google:
          if (targetKey.isEmpty) return false;
          final res = await _dio.get(
            '$targetHost/models',
            queryParameters: {'key': targetKey},
          );
          return res.statusCode == 200;

        case AiProvider.fastapi:
          final res = await _dio.get('$targetHost/health');
          return res.statusCode == 200;
      }
    } catch (e) {
      debugPrint('Connection test failed for $prov ($targetHost): $e');
      return false;
    }
  }

  /// Lists available models on server or returns defaults
  Future<List<String>> listAvailableModels({
    String? customHost,
    String? customApiKey,
    AiProvider? targetProvider,
  }) async {
    final prov = targetProvider ?? provider;
    final targetKey = (customApiKey ?? apiKey).trim();
    final targetHost = (customHost ?? host).replaceAll(RegExp(r'/+$'), '');

    try {
      if (isFastApi || prov == AiProvider.fastapi) {
        final res = await _dio.get('$targetHost/models');
        if (res.data is Map && res.data['models'] is List) {
          return (res.data['models'] as List).map((e) => e.toString()).toList();
        }
      }

      switch (prov) {
        case AiProvider.ollama:
          final res = await _dio.get('$targetHost/api/tags');
          if (res.data is Map && res.data['models'] is List) {
            final list = res.data['models'] as List;
            return list
                .map((m) => (m['name'] ?? m['model'] ?? '').toString())
                .where((s) => s.isNotEmpty)
                .toList();
          }
          break;

        case AiProvider.deepseek:
          if (targetKey.isNotEmpty) {
            final res = await _dio.get(
              '$targetHost/models',
              options: Options(headers: {'Authorization': 'Bearer $targetKey'}),
            );
            if (res.data is Map && res.data['data'] is List) {
              return (res.data['data'] as List)
                  .map((m) => (m['id'] ?? '').toString())
                  .where((s) => s.isNotEmpty)
                  .toList();
            }
          }
          return AppConstants.deepSeekModels;

        case AiProvider.openai:
          if (targetKey.isNotEmpty) {
            final res = await _dio.get(
              '$targetHost/models',
              options: Options(headers: {'Authorization': 'Bearer $targetKey'}),
            );
            if (res.data is Map && res.data['data'] is List) {
              final models = (res.data['data'] as List)
                  .map((m) => (m['id'] ?? '').toString())
                  .where((s) => s.startsWith('gpt-') || s.contains('turbo') || s.startsWith('o1'))
                  .toList();
              if (models.isNotEmpty) return models;
            }
          }
          return AppConstants.openAiModels;

        case AiProvider.claude:
          if (targetKey.isNotEmpty) {
            try {
              final res = await _dio.get(
                '$targetHost/models',
                options: Options(headers: {
                  'x-api-key': targetKey,
                  'anthropic-version': '2023-06-01',
                }),
              );
              if (res.data is Map && res.data['data'] is List) {
                return (res.data['data'] as List)
                    .map((m) => (m['id'] ?? '').toString())
                    .where((s) => s.isNotEmpty)
                    .toList();
              }
            } catch (_) {}
          }
          return AppConstants.claudeModels;

        case AiProvider.google:
          if (targetKey.isNotEmpty) {
            final res = await _dio.get(
              '$targetHost/models',
              queryParameters: {'key': targetKey},
            );
            if (res.data is Map && res.data['models'] is List) {
              final list = (res.data['models'] as List)
                  .map((m) => (m['name'] ?? '').toString().replaceFirst('models/', ''))
                  .where((s) => s.contains('gemini'))
                  .toList();
              if (list.isNotEmpty) return list;
            }
          }
          return AppConstants.googleModels;

        case AiProvider.fastapi:
          break;
      }
    } catch (e) {
      debugPrint('Failed to list models for $prov: $e');
    }

    // Default fallbacks
    switch (prov) {
      case AiProvider.deepseek:
        return AppConstants.deepSeekModels;
      case AiProvider.openai:
        return AppConstants.openAiModels;
      case AiProvider.claude:
        return AppConstants.claudeModels;
      case AiProvider.google:
        return AppConstants.googleModels;
      case AiProvider.ollama:
      case AiProvider.fastapi:
        return AppConstants.textModels;
    }
  }

  /// Generates tags for document content using the configured AI provider
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

    if (isFastApi || provider == AiProvider.fastapi) {
      return _generateTagsViaFastApi(cleanHost, targetModel, text, imageBase64, dims);
    }

    switch (provider) {
      case AiProvider.ollama:
        return _generateTagsViaOllamaWithRetry(cleanHost, targetModel, text, dims, maxRetries);
      case AiProvider.deepseek:
        return _generateTagsViaOpenAiCompatible(cleanHost, targetModel, text, dims, maxRetries, isDeepSeek: true);
      case AiProvider.openai:
        return _generateTagsViaOpenAiCompatible(cleanHost, targetModel, text, dims, maxRetries, isDeepSeek: false);
      case AiProvider.claude:
        return _generateTagsViaClaude(cleanHost, targetModel, text, dims, maxRetries);
      case AiProvider.google:
        return _generateTagsViaGoogle(cleanHost, targetModel, text, dims, maxRetries);
      case AiProvider.fastapi:
        return _generateTagsViaFastApi(cleanHost, targetModel, text, imageBase64, dims);
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

      promptText = _buildPrompt(text, dims, attempt: attempts);
      await Future.delayed(Duration(milliseconds: 500 * attempts));
    }

    return [];
  }

  Future<List<TagItem>> _generateTagsViaOpenAiCompatible(
    String targetHost,
    String model,
    String text,
    List<String> dims,
    int maxRetries, {
    required bool isDeepSeek,
  }) async {
    int attempts = 0;
    String promptText = _buildPrompt(text, dims, attempt: attempts);

    final url = targetHost.endsWith('/chat/completions')
        ? targetHost
        : (targetHost.endsWith('/v1')
            ? '$targetHost/chat/completions'
            : '$targetHost/chat/completions');

    while (attempts < maxRetries) {
      attempts++;
      try {
        final payload = {
          'model': model,
          'messages': [
            {
              'role': 'system',
              'content': '你是一個精準的文獻分析助手。請嚴格以 JSON 格式回應結構化標籤，勿包含額外文字。'
            },
            {
              'role': 'user',
              'content': promptText,
            }
          ],
          'response_format': {'type': 'json_object'},
          'stream': false,
        };

        final response = await _dio.post(
          url,
          data: payload,
          options: Options(headers: {
            'Authorization': 'Bearer ${apiKey.trim()}',
            'Content-Type': 'application/json',
          }),
        );

        if (response.statusCode == 200 && response.data != null) {
          final content = response.data['choices']?[0]?['message']?['content'] ?? '';
          final tags = _parseJsonContent(content);
          if (tags.isNotEmpty) {
            return tags;
          }
        }
      } catch (e) {
        debugPrint('OpenAI/DeepSeek tag generation attempt $attempts failed: $e');
        if (attempts >= maxRetries) rethrow;
      }

      promptText = _buildPrompt(text, dims, attempt: attempts);
      await Future.delayed(Duration(milliseconds: 500 * attempts));
    }

    return [];
  }

  Future<List<TagItem>> _generateTagsViaClaude(
    String targetHost,
    String model,
    String text,
    List<String> dims,
    int maxRetries,
  ) async {
    int attempts = 0;
    String promptText = _buildPrompt(text, dims, attempt: attempts);
    final url = '$targetHost/messages';

    while (attempts < maxRetries) {
      attempts++;
      try {
        final payload = {
          'model': model,
          'max_tokens': 1500,
          'system': '你是一個精準的文獻分析助手。請嚴格以 JSON 格式輸出結構化標籤，勿包含 markdown 標籤以外的任何文字。',
          'messages': [
            {
              'role': 'user',
              'content': promptText,
            }
          ],
        };

        final response = await _dio.post(
          url,
          data: payload,
          options: Options(headers: {
            'x-api-key': apiKey.trim(),
            'anthropic-version': '2023-06-01',
            'Content-Type': 'application/json',
          }),
        );

        if (response.statusCode == 200 && response.data != null) {
          final contentList = response.data['content'] as List?;
          if (contentList != null && contentList.isNotEmpty) {
            final content = contentList[0]['text'] ?? '';
            final tags = _parseJsonContent(content);
            if (tags.isNotEmpty) {
              return tags;
            }
          }
        }
      } catch (e) {
        debugPrint('Claude tag generation attempt $attempts failed: $e');
        if (attempts >= maxRetries) rethrow;
      }

      promptText = _buildPrompt(text, dims, attempt: attempts);
      await Future.delayed(Duration(milliseconds: 500 * attempts));
    }

    return [];
  }

  Future<List<TagItem>> _generateTagsViaGoogle(
    String targetHost,
    String model,
    String text,
    List<String> dims,
    int maxRetries,
  ) async {
    int attempts = 0;
    String promptText = _buildPrompt(text, dims, attempt: attempts);
    final url = '$targetHost/models/$model:generateContent';

    while (attempts < maxRetries) {
      attempts++;
      try {
        final payload = {
          'contents': [
            {
              'role': 'user',
              'parts': [
                {'text': promptText}
              ]
            }
          ],
          'generationConfig': {
            'responseMimeType': 'application/json',
          }
        };

        final response = await _dio.post(
          url,
          queryParameters: {'key': apiKey.trim()},
          data: payload,
          options: Options(headers: {'Content-Type': 'application/json'}),
        );

        if (response.statusCode == 200 && response.data != null) {
          final candidates = response.data['candidates'] as List?;
          if (candidates != null && candidates.isNotEmpty) {
            final parts = candidates[0]?['content']?['parts'] as List?;
            if (parts != null && parts.isNotEmpty) {
              final content = parts[0]['text'] ?? '';
              final tags = _parseJsonContent(content);
              if (tags.isNotEmpty) {
                return tags;
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Google Gemini tag generation attempt $attempts failed: $e');
        if (attempts >= maxRetries) rethrow;
      }

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

      dynamic parsed;
      try {
        parsed = json.decode(cleaned);
      } catch (_) {
        // Fallback: extract the outermost JSON object or array via regex
        final match = RegExp(r'(\{[\s\S]*\}|\[[\s\S]*\])').firstMatch(cleaned);
        if (match != null) {
          parsed = json.decode(match.group(0)!);
        } else {
          rethrow;
        }
      }

      if (parsed is Map && parsed['tags'] is List) {
        return _parseTagItems(parsed['tags'] as List, source: 'ai_text');
      } else if (parsed is List) {
        return _parseTagItems(parsed, source: 'ai_text');
      }
    } catch (e) {
      debugPrint('Error parsing JSON from AI response: $e, content: $content');
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

  /// Generates vector embeddings for a given text using Ollama, FastAPI, OpenAI, or Google Gemini
  Future<List<double>> embed({
    required String text,
    String? model,
  }) async {
    final targetModel = model ?? embeddingModel;
    final cleanHost = host.replaceAll(RegExp(r'/+$'), '');

    if (isFastApi || provider == AiProvider.fastapi) {
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
      }
      return [];
    }

    switch (provider) {
      case AiProvider.ollama:
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
        break;

      case AiProvider.openai:
        try {
          final res = await _dio.post(
            '$cleanHost/embeddings',
            data: {
              'model': targetModel,
              'input': text.length > 2000 ? text.substring(0, 2000) : text,
            },
            options: Options(headers: {
              'Authorization': 'Bearer ${apiKey.trim()}',
              'Content-Type': 'application/json',
            }),
          );
          if (res.statusCode == 200 && res.data is Map && res.data['data'] is List) {
            final dataList = res.data['data'] as List;
            if (dataList.isNotEmpty && dataList[0]['embedding'] is List) {
              return (dataList[0]['embedding'] as List).map((e) => (e as num).toDouble()).toList();
            }
          }
        } catch (e) {
          debugPrint('OpenAI embeddings API error: $e');
        }
        break;

      case AiProvider.google:
        try {
          final url = '$cleanHost/models/$targetModel:embedContent';
          final res = await _dio.post(
            url,
            queryParameters: {'key': apiKey.trim()},
            data: {
              'model': 'models/$targetModel',
              'content': {
                'parts': [
                  {'text': text.length > 2000 ? text.substring(0, 2000) : text}
                ]
              }
            },
            options: Options(headers: {'Content-Type': 'application/json'}),
          );
          if (res.statusCode == 200 && res.data is Map && res.data['embedding'] is Map) {
            final values = res.data['embedding']['values'] as List?;
            if (values != null) {
              return values.map((e) => (e as num).toDouble()).toList();
            }
          }
        } catch (e) {
          debugPrint('Google Gemini embedContent API error: $e');
        }
        break;

      case AiProvider.deepseek:
      case AiProvider.claude:
      case AiProvider.fastapi:
        // DeepSeek and Claude do not provide standard embedding endpoints.
        // Fallback to empty vector gracefully (search will use BM25 + tags).
        break;
    }
    return [];
  }
}
