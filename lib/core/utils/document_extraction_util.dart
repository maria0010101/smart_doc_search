import 'package:smart_doc_search/data/models/knowledge_graph_model.dart';

/// 端側啟發式與正規表示式文件數據抽取工具
/// 提供 RapidDoc 臨床數值/ICD 抽取、GraphifyPDF 學術元數據抽取與三元組啟發式抽取
/// 保證即使在離線或 LLM 未完全回應特定欄位時，系統仍具備高度可靠的抽取能力
class DocumentExtractionUtil {
  // 正規表示式定義
  static final RegExp _doiRegex = RegExp(r'10\.\d{4,9}/[-._;()/:A-Za-z0-9]+', caseSensitive: false);
  static final RegExp _pmidRegex = RegExp(r'(?:PMID|PubMed ID)[:\s]+([0-9]{7,9})', caseSensitive: false);
  static final RegExp _yearRegex = RegExp(r'\b(19\d{2}|20\d{2})\b');
  
  // ICD-10-CM: 英文字母開頭(排除U未定代碼視情況), 兩位數字, 可帶小數點與1~4位字母/數字
  static final RegExp _icd10CmRegex = RegExp(
    r'\b([A-TV-Z][0-9]{2}(?:\.[0-9A-TV-Z]{1,4})?)\b',
    caseSensitive: false,
  );

  // ICD-10-PCS: 嚴格7碼 (排除I與O，首碼為有效章節 0-9, B-D, F-H, X)
  static final RegExp _icd10PcsRegex = RegExp(
    r'\b([0-9B-DF-HX][0-9A-HJ-NP-Z]{6})\b',
  );

  // 常見醫學檢驗指標正規表示式
  static final List<Map<String, dynamic>> _labPatterns = [
    {
      'name': 'HbA1c (糖化血色素)',
      'regex': RegExp(r'(?:HbA1c|糖化血色素|A1C)[:\s]*([<>=]?\s*\d+(?:\.\d+)?)\s*(%|mmol/mol)?', caseSensitive: false),
      'defaultUnit': '%',
      'ref': '< 5.7% (正常), < 7.0% (控制目標)',
    },
    {
      'name': '血壓 (Blood Pressure)',
      'regex': RegExp(r'(?:BP|Blood Pressure|血壓)[:\s]*(\d{2,3}\s*/\s*\d{2,3})\s*(mmHg)?', caseSensitive: false),
      'defaultUnit': 'mmHg',
      'ref': '< 120/80 mmHg',
    },
    {
      'name': '空腹血糖 (Fasting Glucose)',
      'regex': RegExp(r'(?:Fasting glucose|空腹血糖|FPG)[:\s]*([<>=]?\s*\d+(?:\.\d+)?)\s*(mg/dL|mmol/L)?', caseSensitive: false),
      'defaultUnit': 'mg/dL',
      'ref': '70-99 mg/dL',
    },
    {
      'name': '腎絲球過濾率 (eGFR)',
      'regex': RegExp(r'(?:eGFR|腎絲球過濾率)[:\s]*([<>=]?\s*\d+(?:\.\d+)?)\s*(mL/min/1\.73m²)?', caseSensitive: false),
      'defaultUnit': 'mL/min/1.73m²',
      'ref': '≥ 90 mL/min/1.73m²',
    },
    {
      'name': '肌酸酐 (Creatinine)',
      'regex': RegExp(r'(?:Creatinine|肌酸酐|Cr)[:\s]*([<>=]?\s*\d+(?:\.\d+)?)\s*(mg/dL|μmol/L)?', caseSensitive: false),
      'defaultUnit': 'mg/dL',
      'ref': '0.7-1.3 mg/dL',
    },
    {
      'name': '白血球計數 (WBC)',
      'regex': RegExp(r'(?:WBC|白血球)[:\s]*([<>=]?\s*\d+(?:\.\d+)?)\s*(?:[x×*]\s*10\^?[39]/[uμµ]L|/uL|/mm3)?', caseSensitive: false),
      'defaultUnit': '10^3/μL',
      'ref': '4.0-11.0 10^3/μL',
    },
    {
      'name': '低密度膽固醇 (LDL-C)',
      'regex': RegExp(r'(?:LDL-C|LDL|低密度脂蛋白)[:\s]*([<>=]?\s*\d+(?:\.\d+)?)\s*(mg/dL|mmol/L)?', caseSensitive: false),
      'defaultUnit': 'mg/dL',
      'ref': '< 100 mg/dL',
    },
  ];

  /// 抽取學術元數據 (GraphifyPDF)
  static AcademicMetadata extractAcademicMetadata(String text, {String? title}) {
    String? doi;
    final doiMatch = _doiRegex.firstMatch(text);
    if (doiMatch != null) {
      doi = doiMatch.group(0)?.replaceAll(RegExp(r'[\.,;]$'), '');
    }

    int? year;
    // 優先在全文前 2000 字元中尋找年份
    final headerSnippet = text.length > 2000 ? text.substring(0, 2000) : text;
    final yearMatches = _yearRegex.allMatches(headerSnippet);
    for (final m in yearMatches) {
      final y = int.tryParse(m.group(0) ?? '');
      if (y != null && y >= 1970 && y <= DateTime.now().year + 1) {
        year = y;
        break;
      }
    }

    // 啟發式作者抽取
    final authors = <String>[];
    final authorLineRegex = RegExp(
      r'(?:Authors?|作者|By)[:\s]+([^\n\r]+)',
      caseSensitive: false,
    );
    final aMatch = authorLineRegex.firstMatch(headerSnippet);
    if (aMatch != null) {
      final raw = aMatch.group(1) ?? '';
      final split = raw.split(RegExp(r'[,;、]|\band\b', caseSensitive: false));
      for (final a in split) {
        final clean = a.trim();
        if (clean.isNotEmpty && clean.length < 40 && !clean.contains('http')) {
          authors.add(clean);
        }
      }
    }

    // 啟發式期刊名稱抽取
    String? journal;
    final journalRegex = RegExp(
      r'(?:Journal of [A-Za-z\s]+|The Lancet[A-Za-z\s]*|New England Journal of Medicine|BMJ|JAMA|Circulation|Diabetes Care|Annals of Internal Medicine)',
      caseSensitive: false,
    );
    final jMatch = journalRegex.firstMatch(headerSnippet);
    if (jMatch != null) {
      journal = jMatch.group(0)?.trim();
    }

    final citations = <String>[];
    final pmidMatch = _pmidRegex.firstMatch(headerSnippet);
    if (pmidMatch != null && pmidMatch.group(1) != null) {
      citations.add('PMID: ${pmidMatch.group(1)}');
    }

    return AcademicMetadata(
      authors: authors,
      doi: doi,
      publicationYear: year,
      journal: journal,
      keywords: const [],
      citations: citations,
    );
  }

  /// 抽取臨床與疾病分類數據 (RapidDoc)
  static ClinicalFinding extractClinicalFindings(String text) {
    // 1. 抽取 ICD 代碼
    final foundIcd = <String, IcdCodeItem>{};
    for (final m in _icd10CmRegex.allMatches(text)) {
      final code = m.group(0)?.toUpperCase();
      if (code != null && code.length >= 3 && _isValidIcdPrefix(code)) {
        foundIcd[code] = IcdCodeItem(
          code: code,
          title: _lookupCommonIcdName(code),
          system: 'ICD-10-CM',
        );
      }
    }

    for (final m in _icd10PcsRegex.allMatches(text)) {
      final code = m.group(0)?.toUpperCase();
      if (code != null && RegExp(r'\d').hasMatch(code) && !foundIcd.containsKey(code)) {
        foundIcd[code] = IcdCodeItem(
          code: code,
          title: '處置手術碼 ($code)',
          system: 'ICD-10-PCS',
        );
      }
    }

    // 2. 抽取檢驗數據
    final labValues = <LabValueItem>[];
    for (final pattern in _labPatterns) {
      final name = pattern['name'] as String;
      final regex = pattern['regex'] as RegExp;
      final defaultUnit = pattern['defaultUnit'] as String;
      final ref = pattern['ref'] as String;

      final match = regex.firstMatch(text);
      if (match != null) {
        final val = match.group(1)?.trim();
        final unit = match.groupCount >= 2 && match.group(2) != null ? match.group(2)!.trim() : defaultUnit;
        if (val != null && val.isNotEmpty) {
          labValues.add(LabValueItem(
            testName: name,
            value: val,
            unit: unit.isNotEmpty ? unit : defaultUnit,
            referenceRange: ref,
          ));
        }
      }
    }

    // 3. 抽取常見主要診斷與處置術語
    final secondary = <String>[];
    final procedures = <String>[];

    final diagnosisKeywords = [
      '第2型糖尿病', 'Type 2 Diabetes', '高血壓', 'Hypertension', '冠狀動脈疾病',
      'Coronary Artery Disease', '心臟衰竭', 'Heart Failure', '慢性腎臟病',
      'Chronic Kidney Disease', '缺血性腦中風', 'Ischemic Stroke', '肺炎', 'Pneumonia',
      '心肌梗塞', 'Myocardial Infarction', '心房顫動', 'Atrial Fibrillation',
    ];

    for (final kw in diagnosisKeywords) {
      if (text.contains(kw)) {
        secondary.add(kw);
      }
    }

    final procedureKeywords = [
      '心導管檢查', '冠狀動脈氣球擴張術', '支架置放術', '血液透析', '胰島素注射',
      'SGLT2抑制劑處方', '血管攝影', '胸部X光', '超音波檢查', '內視鏡檢',
      'Catheterization', 'Stent', 'Angioplasty', 'Hemodialysis',
    ];

    for (final kw in procedureKeywords) {
      if (text.contains(kw)) {
        procedures.add(kw);
      }
    }

    String? principal;
    if (secondary.isNotEmpty) {
      principal = secondary.first;
    }

    return ClinicalFinding(
      principalDiagnosis: principal,
      secondaryDiagnoses: secondary.take(6).toList(),
      procedures: procedures.take(6).toList(),
      labValues: labValues,
      icdCodes: foundIcd.values.take(8).toList(),
    );
  }

  /// 抽取知識三元組 (llm-knowledge-graph 啟發式備援)
  static List<KnowledgeTriplet> extractKnowledgeTriplets(String text) {
    final triplets = <KnowledgeTriplet>[];
    final seen = <String>{};

    final relationPatterns = [
      // 臨床因果/併發症
      RegExp(r'([\u4e00-\u9fa5A-Za-z0-9]+)\s*(?:會導致|可引發|造成|併發|增加風險)\s*([\u4e00-\u9fa5A-Za-z0-9]+)'),
      // 治療/控制關聯
      RegExp(r'([\u4e00-\u9fa5A-Za-z0-9]+)\s*(?:用於治療|可控制|顯著改善|適用於)\s*([\u4e00-\u9fa5A-Za-z0-9]+)'),
      // 診斷/檢驗關聯
      RegExp(r'([\u4e00-\u9fa5A-Za-z0-9]+)\s*(?:診斷標準為|以檢測|反映出)\s*([\u4e00-\u9fa5A-Za-z0-9]+)'),
      // 英文關係
      RegExp(r'([A-Za-z0-9\s-]{3,25})\s+(?:causes|leads to|treats|prevents|indicates)\s+([A-Za-z0-9\s-]{3,25})', caseSensitive: false),
    ];

    for (final pattern in relationPatterns) {
      for (final m in pattern.allMatches(text)) {
        final sub = m.group(1)?.trim();
        final obj = m.group(2)?.trim();
        if (sub != null && obj != null && sub.isNotEmpty && obj.isNotEmpty && sub != obj && sub.length < 30 && obj.length < 30) {
          final key = '$sub->$obj';
          if (!seen.contains(key)) {
            seen.add(key);
            String predicate = '關聯於';
            if (m.pattern.toString().contains('治療') || m.pattern.toString().contains('treats')) {
              predicate = '治療/改善';
            } else if (m.pattern.toString().contains('導致') || m.pattern.toString().contains('causes')) {
              predicate = '導致/併發';
            } else if (m.pattern.toString().contains('診斷') || m.pattern.toString().contains('indicates')) {
              predicate = '診斷指標';
            }

            triplets.add(KnowledgeTriplet(
              subject: sub,
              predicate: predicate,
              object: obj,
              confidence: 0.85,
            ));
          }
        }
      }
    }

    return triplets.take(12).toList();
  }

  static bool _isValidIcdPrefix(String code) {
    final firstChar = code[0].toUpperCase();
    // ICD-10-CM 章節範圍 A-N, I, E 等等 (排除無效字母)
    return 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.contains(firstChar) && firstChar != 'U';
  }

  static String _lookupCommonIcdName(String code) {
    final prefix = code.split('.').first.toUpperCase();
    switch (prefix) {
      case 'E11': return '第2型糖尿病';
      case 'E10': return '第1型糖尿病';
      case 'I10': return '本態性高血壓';
      case 'I25': return '慢性缺血性心臟病';
      case 'I21': return '急性心肌梗塞';
      case 'I50': return '心臟衰竭';
      case 'I63': return '腦梗塞 (缺血性中風)';
      case 'N18': return '慢性腎臟疾病';
      case 'J18': return '肺炎';
      case 'J44': return '慢性阻塞性肺病';
      case 'C34': return '支氣管及肺惡性腫瘤';
      case 'K21': return '胃食道逆流';
      default: return '疾病分類碼 ($code)';
    }
  }
}
