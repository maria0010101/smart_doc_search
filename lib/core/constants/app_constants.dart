class AppConstants {
  // Database & Native Channel
  static const String koredbChannel = 'com.smartdoc.search/koredb';
  static const String nativeToolsChannel = 'com.smartdoc.search/native_tools';

  // Default Ollama Configurations
  static const String defaultOllamaHost = 'http://192.168.1.100:11434';
  static const String defaultTextTagModel = 'qwen2.5:3b';
  static const String defaultEmbeddingModel = 'nomic-embed-text';
  static const String defaultVisionModel = 'qwen2.5-vl:3b';

  // Candidate Models
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

  // Document Tag Dimensions
  static const List<String> defaultTagDimensions = [
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
  static const List<String> supportedImageExt = ['jpg', 'jpeg', 'png', 'webp'];
  static const List<String> supportedPptExt = ['ppt', 'pptx'];

  // SharedPreferences Keys
  static const String prefOllamaHost = 'pref_ollama_host';
  static const String prefTextModel = 'pref_text_model';
  static const String prefEmbeddingModel = 'pref_embedding_model';
  static const String prefFastApiEnabled = 'pref_fastapi_enabled';
  static const String prefFastApiHost = 'pref_fastapi_host';
  static const String prefDarkMode = 'pref_dark_mode';
  static const String prefEnableVector = 'pref_enable_vector';
}
