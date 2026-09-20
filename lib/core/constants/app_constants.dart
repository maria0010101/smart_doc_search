enum AiProvider {
  ollama('ollama', 'Ollama (本地/區網)'),
  fastapi('fastapi', 'FastAPI (中間層)'),
  deepseek('deepseek', 'DeepSeek API'),
  openai('openai', 'OpenAI GPT API'),
  claude('claude', 'Anthropic Claude API'),
  google('google', 'Google Gemini API');

  final String id;
  final String displayName;
  const AiProvider(this.id, this.displayName);

  static AiProvider fromId(String? id) {
    return AiProvider.values.firstWhere(
      (p) => p.id == id,
      orElse: () => AiProvider.ollama,
    );
  }
}

class AppConstants {
  // App Version
  static const String appVersion = '0.1.3';

  // Database & Native Channel
  static const String koredbChannel = 'com.smartdoc.search/koredb';
  static const String nativeToolsChannel = 'com.smartdoc.search/native_tools';

  // Default Hosts
  static const String defaultOllamaHost = 'http://192.168.1.100:11434';
  static const String defaultFastApiHost = 'http://192.168.1.100:8000';
  static const String defaultDeepSeekHost = 'https://api.deepseek.com';
  static const String defaultOpenAiHost = 'https://api.openai.com/v1';
  static const String defaultClaudeHost = 'https://api.anthropic.com/v1';
  static const String defaultGoogleHost = 'https://generativelanguage.googleapis.com/v1beta';

  // Default Models
  static const String defaultTextTagModel = 'qwen2.5:3b';
  static const String defaultEmbeddingModel = 'nomic-embed-text';
  static const String defaultVisionModel = 'qwen2.5-vl:3b';

  static const String defaultDeepSeekModel = 'deepseek-chat';
  static const String defaultOpenAiModel = 'gpt-4o-mini';
  static const String defaultOpenAiEmbeddingModel = 'text-embedding-3-small';
  static const String defaultClaudeModel = 'claude-3-5-haiku-20241022';
  static const String defaultGoogleModel = 'gemini-1.5-flash';
  static const String defaultGoogleEmbeddingModel = 'text-embedding-004';

  // Candidate Models per Provider
  static const List<String> textModels = [
    'qwen2.5:3b',
    'qwen2.5:1.5b',
    'llama3.2:3b',
    'mistral:7b',
  ];

  static const List<String> embeddingModels = [
    'nomic-embed-text',
    'all-minilm',
    'bge-m3',
  ];

  static const List<String> visionModels = [
    'qwen2.5-vl:3b',
    'llava:7b',
    'moondream:1.8b',
  ];

  static const List<String> deepSeekModels = [
    'deepseek-chat',
    'deepseek-reasoner',
  ];

  static const List<String> openAiModels = [
    'gpt-4o-mini',
    'gpt-4o',
    'gpt-3.5-turbo',
  ];

  static const List<String> openAiEmbeddingModels = [
    'text-embedding-3-small',
    'text-embedding-3-large',
  ];

  static const List<String> claudeModels = [
    'claude-3-5-haiku-20241022',
    'claude-3-5-sonnet-20241022',
    'claude-3-haiku-20240307',
  ];

  static const List<String> googleModels = [
    'gemini-1.5-flash',
    'gemini-1.5-pro',
    'gemini-2.0-flash',
  ];

  static const List<String> googleEmbeddingModels = [
    'text-embedding-004',
  ];

  // Document Tag Dimensions
  static const List<String> defaultTagDimensions = [
    '醫學術語',
    '疾病/症狀',
    '疾病分類編碼',
    '主題',
    '領域',
    '方法',
    '對象',
    '結論',
    '文檔類型',
    '語言',
    '年份',
    '作者/機構',
  ];

  // Hybrid Search Default Weights
  static const double weightKeyword = 0.4;
  static const double weightVector = 0.4;
  static const double weightTag = 0.2;

  // File Types
  static const List<String> supportedPdfExt = ['pdf'];
  static const List<String> supportedTextExt = ['txt', 'md', 'markdown', 'csv', 'json', 'log'];
  static const List<String> supportedImageExt = ['jpg', 'jpeg', 'png', 'webp'];
  static const List<String> supportedPptExt = ['ppt', 'pptx'];

  // SharedPreferences Keys
  static const String prefAiProvider = 'pref_ai_provider';

  static const String prefOllamaHost = 'pref_ollama_host';
  static const String prefTextModel = 'pref_text_model';
  static const String prefEmbeddingModel = 'pref_embedding_model';

  static const String prefFastApiEnabled = 'pref_fastapi_enabled';
  static const String prefFastApiHost = 'pref_fastapi_host';

  static const String prefDeepSeekApiKey = 'pref_deepseek_api_key';
  static const String prefDeepSeekHost = 'pref_deepseek_host';
  static const String prefDeepSeekModel = 'pref_deepseek_model';

  static const String prefOpenAiApiKey = 'pref_openai_api_key';
  static const String prefOpenAiHost = 'pref_openai_host';
  static const String prefOpenAiModel = 'pref_openai_model';
  static const String prefOpenAiEmbeddingModel = 'pref_openai_embedding_model';

  static const String prefClaudeApiKey = 'pref_claude_api_key';
  static const String prefClaudeHost = 'pref_claude_host';
  static const String prefClaudeModel = 'pref_claude_model';

  static const String prefGoogleApiKey = 'pref_google_api_key';
  static const String prefGoogleHost = 'pref_google_host';
  static const String prefGoogleModel = 'pref_google_model';
  static const String prefGoogleEmbeddingModel = 'pref_google_embedding_model';

  static const String prefDarkMode = 'pref_dark_mode';
  static const String prefEnableVector = 'pref_enable_vector';
  static const String prefDiseaseClassificationMode = 'pref_disease_classification_mode';
}
