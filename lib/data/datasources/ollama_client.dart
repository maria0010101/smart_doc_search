import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:smart_doc_search/core/constants/app_constants.dart';
import 'package:smart_doc_search/core/utils/text_normalizer.dart';
import 'package:smart_doc_search/data/models/document_model.dart';

/// Structured result of AI document analysis containing:
/// - Categorized tags (medical terms, diseases/symptoms, ICD classification codes, etc.)
/// - Full executive summary
/// - Dedicated Chinese summary (for English / foreign literature to confirm target at a glance)
/// - Detected language
class AiAnalysisResult {
  final List<TagItem> tags;
  final String summary;
  final String chineseSummary;
  final String detectedLanguage;
  final List<String> medicalTerms;
  final List<String> diseasesAndSymptoms;
  final List<String> classificationCodes;

  AiAnalysisResult({
    required this.tags,
    this.summary = '',
    this.chineseSummary = '',
    this.detectedLanguage = 'zh-TW',
    this.medicalTerms = const [],
    this.diseasesAndSymptoms = const [],
    this.classificationCodes = const [],
  });

  /// Best summary to display at top of detail view (prefer Chinese summary for Chinese readers)
  String get displaySummary {
    if (chineseSummary.isNotEmpty) return chineseSummary;
    if (summary.isNotEmpty) return summary;
    return '無摘要內容';
  }
}

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

  /// Full AI Document Analysis:
  /// 1. Extracts structured tags: 醫學術語, 疾病/症狀, 疾病分類編碼 (ICD), 主題, 領域, 方法, 對象, 結論
  /// 2. Produces executive summary for quick verification of query target
  /// 3. If English / foreign text, produces Chinese summary explanation
  Future<AiAnalysisResult> generateAnalysis({
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
      return _generateAnalysisViaFastApi(cleanHost, targetModel, text, imageBase64, dims);
    }

    switch (provider) {
      case AiProvider.ollama:
        return _generateAnalysisViaOllamaWithRetry(cleanHost, targetModel, text, dims, maxRetries);
      case AiProvider.deepseek:
        return _generateAnalysisViaOpenAiCompatible(cleanHost, targetModel, text, dims, maxRetries, isDeepSeek: true);
      case AiProvider.openai:
        return _generateAnalysisViaOpenAiCompatible(cleanHost, targetModel, text, dims, maxRetries, isDeepSeek: false);
      case AiProvider.claude:
        return _generateAnalysisViaClaude(cleanHost, targetModel, text, dims, maxRetries);
      case AiProvider.google:
        return _generateAnalysisViaGoogle(cleanHost, targetModel, text, dims, maxRetries);
      case AiProvider.fastapi:
        return _generateAnalysisViaFastApi(cleanHost, targetModel, text, imageBase64, dims);
    }
  }

  /// Backward-compatible tag generator
  Future<List<TagItem>> generateTags({
    required String text,
    String? imageBase64,
    List<String>? dimensions,
    String? model,
    int maxRetries = 3,
  }) async {
    final result = await generateAnalysis(
      text: text,
      imageBase64: imageBase64,
      dimensions: dimensions,
      model: model,
      maxRetries: maxRetries,
    );
    return result.tags;
  }

  Future<AiAnalysisResult> _generateAnalysisViaFastApi(
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
        final summary = (res.data['summary'] ?? '').toString();
        final chSummary = (res.data['chinese_summary'] ?? '').toString();
        return AiAnalysisResult(
          tags: _parseTagItems(rawTags, source: imageBase64 != null ? 'ai_image' : 'ai_text'),
          summary: summary,
          chineseSummary: chSummary,
        );
      }
    } catch (e) {
      debugPrint('FastAPI generate-tags error: $e');
      rethrow;
    }
    return AiAnalysisResult(tags: []);
  }

  Future<AiAnalysisResult> _generateAnalysisViaOllamaWithRetry(
    String targetHost,
    String model,
    String text,
    List<String> dims,
    int maxRetries,
  ) async {
    int attempts = 0;
    String promptText = _buildAnalysisPrompt(text, dims, attempt: attempts);

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
          final result = _parseJsonAnalysis(content);
          if (result.tags.isNotEmpty || result.summary.isNotEmpty) {
            return result;
          }
        }
      } catch (e) {
        debugPrint('Ollama analysis attempt $attempts failed: $e');
        if (attempts >= maxRetries) rethrow;
      }

      promptText = _buildAnalysisPrompt(text, dims, attempt: attempts);
      await Future.delayed(Duration(milliseconds: 500 * attempts));
    }

    return AiAnalysisResult(tags: []);
  }

  Future<AiAnalysisResult> _generateAnalysisViaOpenAiCompatible(
    String targetHost,
    String model,
    String text,
    List<String> dims,
    int maxRetries, {
    required bool isDeepSeek,
  }) async {
    int attempts = 0;
    String promptText = _buildAnalysisPrompt(text, dims, attempt: attempts);

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
              'content':
                  '你是一個精準的專業文獻與醫學分析助手。請嚴格以 JSON 格式回應，包含醫學術語、疾病症狀標籤、疾病分類編碼（如 ICD）、核心摘要與英文文獻之中文說明。'
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
          final result = _parseJsonAnalysis(content);
          if (result.tags.isNotEmpty || result.summary.isNotEmpty) {
            return result;
          }
        }
      } catch (e) {
        debugPrint('OpenAI/DeepSeek analysis attempt $attempts failed: $e');
        if (attempts >= maxRetries) rethrow;
      }

      promptText = _buildAnalysisPrompt(text, dims, attempt: attempts);
      await Future.delayed(Duration(milliseconds: 500 * attempts));
    }

    return AiAnalysisResult(tags: []);
  }

  Future<AiAnalysisResult> _generateAnalysisViaClaude(
    String targetHost,
    String model,
    String text,
    List<String> dims,
    int maxRetries,
  ) async {
    int attempts = 0;
    String promptText = _buildAnalysisPrompt(text, dims, attempt: attempts);
    final url = '$targetHost/messages';

    while (attempts < maxRetries) {
      attempts++;
      try {
        final payload = {
          'model': model,
          'max_tokens': 2048,
          'system':
              '你是一個精準的專業文獻與醫學分析助手。請嚴格以 JSON 格式輸出結構化分析，包含醫學術語、疾病症狀、ICD分類碼、核心摘要及英文文獻中文對照說明。勿輸出任何 markdown 區塊外的文字說明。',
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
            final result = _parseJsonAnalysis(content);
            if (result.tags.isNotEmpty || result.summary.isNotEmpty) {
              return result;
            }
          }
        }
      } catch (e) {
        debugPrint('Claude analysis attempt $attempts failed: $e');
        if (attempts >= maxRetries) rethrow;
      }

      promptText = _buildAnalysisPrompt(text, dims, attempt: attempts);
      await Future.delayed(Duration(milliseconds: 500 * attempts));
    }

    return AiAnalysisResult(tags: []);
  }

  Future<AiAnalysisResult> _generateAnalysisViaGoogle(
    String targetHost,
    String model,
    String text,
    List<String> dims,
    int maxRetries,
  ) async {
    int attempts = 0;
    String promptText = _buildAnalysisPrompt(text, dims, attempt: attempts);
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
              final result = _parseJsonAnalysis(content);
              if (result.tags.isNotEmpty || result.summary.isNotEmpty) {
                return result;
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Google Gemini analysis attempt $attempts failed: $e');
        if (attempts >= maxRetries) rethrow;
      }

      promptText = _buildAnalysisPrompt(text, dims, attempt: attempts);
      await Future.delayed(Duration(milliseconds: 500 * attempts));
    }

    return AiAnalysisResult(tags: []);
  }

  String _buildAnalysisPrompt(String text, List<String> dims, {int attempt = 0}) {
    // Expand to modern LLM capacity (up to 35,000 characters)
    final truncatedText = text.length > 35000 ? text.substring(0, 35000) : text;
    final dimListStr = dims.join('、');

    return '''你是一個專業的醫學與學術文獻深度分析專家。請仔細閱讀下方提供的【文獻完整全文內容】，進行全面深度分析、多維特徵辨識、醫學術語抽取、疾病與症狀分類編碼，並撰寫結構化摘要。

【重大要求 1 - 標籤辨識必須基於全文內容進行辨識】：
- 標籤辨識絕不能僅僅依據標題或摘要文件，必須徹底基於下方的【全文內容】進行全面掃描與抽取！
- 請深入全文的所有章節、標題、內文段落、表格數據、病歷診斷、討論與結論，抽取所有涉及的：
  a) 醫學術語（medical_terms）：核心醫學專有名詞、解剖構造、病理生理學術語、治療技術、藥物成分。
  b) 疾病/症狀（diseases_and_symptoms）：全文探討或提及的所有具體疾病名稱、臨床綜合徵、主要體徵與症狀。
  c) 疾病分類編碼（classification_codes）：全文中提及或對應之 ICD-10-CM / ICD-10-PCS / ICD-11 或醫學標準分類編碼。
  d) 其他多維標籤：從 $dimListStr 等維度提取具有檢索價值的專業標籤。

【重大要求 2 - 文獻摘要說明必須以全文內容進行摘要，包含各標題內文字】：
- 文獻核心摘要（summary）與英文文獻中文摘要說明（chinese_summary）必須全面涵蓋【全文內容】，嚴格包含文獻中出現的「各章節標題」以及「各標題底下所屬內文」。
- 請以清晰結構化方式呈現：研究背景主旨、各主要章節/標題論述精華、具體探討之疾病病例與處置方法、以及全文最終結論與編碼指導（約 200-450 字）。
- 若原文為英文或外文，chinese_summary 必須提供詳盡的繁體中文摘要說明，明確總結各標題與內文核心，以便讀者在文獻詳情頁頂端立即確認是否為查詢目標！

請嚴格輸出合法的 JSON 格式，不要輸出任何額外文字：
{
  "detected_language": "en 或 zh",
  "summary": "涵蓋全文各章節標題與內文字的完整摘要...",
  "chinese_summary": "針對英文文獻之繁體中文摘要說明（深入涵蓋各標題內文重點）...",
  "medical_terms": ["醫學專有名詞1", "醫學專有名詞2"],
  "diseases_and_symptoms": ["疾病或症狀名稱1", "疾病或症狀名稱2"],
  "classification_codes": ["ICD-10/11編碼", "相關分類代碼"],
  "tags": [
    {"name": "標籤名稱", "category": "疾病/症狀 或 醫學術語 或 疾病分類編碼 或 主題", "confidence": 0.95}
  ]
}

文獻完整全文內容：
---
$truncatedText
---
''';
  }

  AiAnalysisResult _parseJsonAnalysis(String content) {
    try {
      var cleaned = content.trim();
      if (cleaned.startsWith('```')) {
        cleaned = cleaned.replaceAll(RegExp(r'^```(json)?|```$', multiLine: true), '').trim();
      }

      dynamic parsed;
      try {
        parsed = json.decode(cleaned);
      } catch (_) {
        final match = RegExp(r'(\{[\s\S]*\}|\[[\s\S]*\])').firstMatch(cleaned);
        if (match != null) {
          parsed = json.decode(match.group(0)!);
        } else {
          rethrow;
        }
      }

      if (parsed is Map) {
        final summary = (parsed['summary'] ?? '').toString();
        final chineseSummary = (parsed['chinese_summary'] ?? parsed['chineseSummary'] ?? '').toString();
        final lang = (parsed['detected_language'] ?? parsed['language'] ?? 'zh-TW').toString();

        final medTerms = (parsed['medical_terms'] as List?)?.map((e) => e.toString()).toList() ?? [];
        final diseases = (parsed['diseases_and_symptoms'] as List?)?.map((e) => e.toString()).toList() ?? [];
        final codes = (parsed['classification_codes'] as List?)?.map((e) => e.toString()).toList() ?? [];

        final rawTags = (parsed['tags'] as List?) ?? [];
        final parsedTags = _parseTagItems(rawTags, source: 'ai_analysis');

        // Automatically ensure items from medical arrays exist as tags
        final existingNames = parsedTags.map((t) => t.name.toLowerCase()).toSet();

        for (final d in diseases) {
          final norm = TextNormalizer.normalizeTag(d);
          if (norm.isNotEmpty && !existingNames.contains(norm.toLowerCase())) {
            existingNames.add(norm.toLowerCase());
            parsedTags.add(TagItem(
              id: 'med_d_${DateTime.now().microsecondsSinceEpoch}_${parsedTags.length}',
              name: norm,
              category: '疾病/症狀',
              confidence: 0.95,
              source: 'ai_analysis',
            ));
          }
        }

        for (final c in codes) {
          final norm = TextNormalizer.normalizeTag(c);
          if (norm.isNotEmpty && !existingNames.contains(norm.toLowerCase())) {
            existingNames.add(norm.toLowerCase());
            parsedTags.add(TagItem(
              id: 'med_c_${DateTime.now().microsecondsSinceEpoch}_${parsedTags.length}',
              name: norm,
              category: '疾病分類編碼',
              confidence: 0.92,
              source: 'ai_analysis',
            ));
          }
        }

        for (final m in medTerms) {
          final norm = TextNormalizer.normalizeTag(m);
          if (norm.isNotEmpty && !existingNames.contains(norm.toLowerCase())) {
            existingNames.add(norm.toLowerCase());
            parsedTags.add(TagItem(
              id: 'med_t_${DateTime.now().microsecondsSinceEpoch}_${parsedTags.length}',
              name: norm,
              category: '醫學術語',
              confidence: 0.90,
              source: 'ai_analysis',
            ));
          }
        }

        return AiAnalysisResult(
          tags: parsedTags,
          summary: summary,
          chineseSummary: chineseSummary,
          detectedLanguage: lang,
          medicalTerms: medTerms,
          diseasesAndSymptoms: diseases,
          classificationCodes: codes,
        );
      } else if (parsed is List) {
        final tags = _parseTagItems(parsed, source: 'ai_analysis');
        return AiAnalysisResult(tags: tags);
      }
    } catch (e) {
      debugPrint('Error parsing analysis JSON: $e, content: $content');
    }
    return AiAnalysisResult(tags: []);
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
        // DeepSeek and Claude do not provide standard public vector embedding endpoints.
        // Handled via local BM25 + inverted index seamlessly.
        break;
    }
    return [];
  }
}
