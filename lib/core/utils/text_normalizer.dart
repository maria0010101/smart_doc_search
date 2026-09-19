class TextNormalizer {
  /// Known synonym map for literature tags
  static final Map<String, String> synonymMap = {
    'ml': '機器學習',
    'machine learning': '機器學習',
    'dl': '深度學習',
    'deep learning': '深度學習',
    'ai': '人工智慧',
    'artificial intelligence': '人工智慧',
    'nlp': '自然語言處理',
    'natural language processing': '自然語言處理',
    'cv': '電腦視覺',
    'computer vision': '電腦視覺',
    'llm': '大型語言模型',
    'large language model': '大型語言模型',
    'rag': '檢索增強生成',

    // Medical Terminology & Disease abbreviations
    'dm': '糖尿病',
    'diabetes': '糖尿病',
    'htn': '高血壓',
    'hypertension': '高血壓',
    'cad': '冠狀動脈心臟病',
    'copd': '慢性阻塞性肺病',
    'ckd': '慢性腎臟病',
    'esrd': '末期腎臟病',
    'ami': '急性心肌梗塞',
    'cva': '腦中風',
    'stroke': '腦中風',
    'covid': '新冠肺炎',
    'covid-19': '新冠肺炎',
    'hf': '心力衰竭',
    'heart failure': '心力衰竭',
    'ad': '阿茲海默症',
    'alzheimer': '阿茲海默症',
    'pd': '巴金森氏症',
    'parkinson': '巴金森氏症',
    'icd-10': 'ICD-10疾病編碼',
    'icd-11': 'ICD-11疾病編碼',
    'icd': '疾病分類編碼',
  };

  /// Normalizes tag strings:
  /// 1. Converts full-width characters to half-width
  /// 2. Trims leading/trailing whitespace
  /// 3. Normalizes casing
  /// 4. Maps known aliases/synonyms
  static String normalizeTag(String tag) {
    if (tag.isEmpty) return '';

    // Convert fullwidth to halfwidth
    final buffer = StringBuffer();
    for (int i = 0; i < tag.length; i++) {
      final code = tag.codeUnitAt(i);
      if (code >= 0xFF01 && code <= 0xFF5E) {
        // Fullwidth ASCII variants (65281 - 65374) -> ASCII (33 - 126)
        buffer.writeCharCode(code - 0xFEE0);
      } else if (code == 0x3000) {
        // Fullwidth space -> halfwidth space
        buffer.writeCharCode(0x20);
      } else {
        buffer.writeCharCode(code);
      }
    }

    var normalized = buffer.toString().trim();

    // Check lowercase synonym match
    final lower = normalized.toLowerCase();
    if (synonymMap.containsKey(lower)) {
      return synonymMap[lower]!;
    }

    return normalized;
  }

  /// Deduplicates and normalizes a list of tag names
  static List<String> cleanTagList(List<String> tags) {
    final seen = <String>{};
    final result = <String>[];

    for (final t in tags) {
      final norm = normalizeTag(t);
      final key = norm.toLowerCase();
      if (norm.isNotEmpty && !seen.contains(key)) {
        seen.add(key);
        result.add(norm);
      }
    }
    return result;
  }
}
