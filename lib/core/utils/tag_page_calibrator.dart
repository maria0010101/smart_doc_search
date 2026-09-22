import 'package:smart_doc_search/core/utils/text_normalizer.dart';
import 'package:smart_doc_search/data/models/document_model.dart';

/// 標籤與全文檢索頁碼校準器
/// 專門解決「目錄判斷誤導以致許多標籤呈現索引頁數皆在第一頁」的問題，
/// 確保標籤與檢索命中頁碼皆能精準指向原始文獻中實質探討內容之真實頁數。
class TagPageCalibrator {
  /// 判斷特定頁面是否為「目錄頁 (Table of Contents)」或「封面/扉頁」
  static bool isTableOfContentsPage(PageItem page) {
    if (page.ocrText.isEmpty) return false;
    final text = page.ocrText.toLowerCase();

    // 1. 常見目錄/索引關鍵字
    final tocKeywords = [
      '目錄',
      '目 錄',
      '目  錄',
      'table of contents',
      'contents',
      'table of content',
      'content',
      'content table',
      'index',
      '簡介',
      '封面',
      '版權頁',
      'editorial board',
    ];

    for (final kw in tocKeywords) {
      if (text.contains(kw)) {
        return true;
      }
    }

    // 2. 目錄特有的引導線特徵（例如「...... 12」或「…… 5」或「--- 24」）
    final dottedLeaderPattern = RegExp(r'(\.{3,}|…{2,}|[-—_]{3,})\s*[0-9]+');
    if (dottedLeaderPattern.hasMatch(text)) {
      return true;
    }

    // 3. 重複出現章節與對應頁碼的目錄排版
    final chapterPagePattern = RegExp(r'(?:第\s*[0-9一二三四五六七八九十]+\s*[章節篇]|chapter\s*[0-9]+)[\s\S]*?[0-9]+', caseSensitive: false);
    final chapterMatches = chapterPagePattern.allMatches(text).length;
    if (chapterMatches >= 2) {
      return true;
    }

    return false;
  }

  /// 若目錄頁有指引該標籤所屬章節之目標頁碼，解析該目標頁數
  static int? extractTocTargetPage(String tocText, String tagName, int maxPages) {
    if (tocText.isEmpty || tagName.isEmpty) return null;
    final escapedTag = RegExp.escape(tagName.toLowerCase());

    // 匹配如「糖尿病 ...... 15」、「心血管照護 (P.8)」、「第2型糖尿病 12」等目錄條目
    final patterns = [
      RegExp('$escapedTag[^\\n\\r0-9]{0,40}(?:\\.{2,}|…{2,}|[-—_]{2,}|\\s{2,}|(?:第|\\(p\\.?|\\[p\\.?))\\s*([0-9]+)', caseSensitive: false),
      RegExp('$escapedTag[\\s\\S]{0,30}?(?:p\\.?|第)?\\s*([0-9]+)\\s*頁?', caseSensitive: false),
    ];

    for (final p in patterns) {
      final match = p.firstMatch(tocText.toLowerCase());
      if (match != null) {
        final targetStr = match.group(1);
        final pageNum = int.tryParse(targetStr ?? '');
        if (pageNum != null && pageNum >= 1 && pageNum <= maxPages) {
          return pageNum;
        }
      }
    }

    return null;
  }

  /// 針對單一標籤/關鍵字，全面掃描所有頁面找出實質討論內容最多的正確頁碼
  static int? findSubstantivePageForKeyword(
    String keyword,
    List<PageItem> pages, {
    int? aiSuggestedPage,
  }) {
    if (pages.isEmpty) return aiSuggestedPage;
    if (pages.length == 1) return 1;

    final normalizedKw = TextNormalizer.normalizeTag(keyword).toLowerCase();
    if (normalizedKw.isEmpty) return aiSuggestedPage;

    // 檢查第 1 頁（與第 2 頁）是否為目錄
    final page1IsTOC = isTableOfContentsPage(pages.first);
    final page2IsTOC = pages.length > 1 && isTableOfContentsPage(pages[1]);

    // 若第 1 頁是目錄，嘗試從目錄文字解析目標頁碼
    if (page1IsTOC) {
      final tocTarget = extractTocTargetPage(pages.first.ocrText, normalizedKw, pages.length);
      if (tocTarget != null && tocTarget > 1) {
        return tocTarget;
      }
    }

    int bestPage = -1;
    int maxSubstantiveScore = 0;
    final pagesWithOccurrences = <int>[];

    for (final page in pages) {
      final pNum = page.pageNumber;
      final text = page.ocrText.toLowerCase();

      final count = RegExp(RegExp.escape(normalizedKw), caseSensitive: false).allMatches(text).length;

      if (count > 0) {
        pagesWithOccurrences.add(pNum);

        int score = count * 2;

        // 若出現在版面標題 (Title / Header)，大幅增加實質權重
        for (final block in page.layoutBlocks) {
          if (block.text.toLowerCase().contains(normalizedKw)) {
            if (block.type == 'title' || block.type == 'header') {
              score += 6;
            }
          }
        }

        // ⚠️ 若此頁為目錄頁（通常是第 1 頁或第 2 頁），將其權重歸零或極大幅削弱，避免目錄條目搶走內文頁面
        if ((pNum == 1 && page1IsTOC) || (pNum == 2 && page2IsTOC)) {
          score = 0;
        }

        if (score > maxSubstantiveScore) {
          maxSubstantiveScore = score;
          bestPage = pNum;
        }
      }
    }

    // 優先序 1: AI 原始標註的頁碼大於 1 且合法
    if (aiSuggestedPage != null && aiSuggestedPage > 1 && aiSuggestedPage <= pages.length) {
      // 若 AI 標註的頁碼本身就包含該詞，或內文實質頁數未強烈否定，採信 AI 頁碼
      if (pagesWithOccurrences.contains(aiSuggestedPage) || bestPage == -1) {
        return aiSuggestedPage;
      }
    }

    // 優先序 2: 內文中實質出現次數最多且非目錄的頁面
    if (bestPage > 0) {
      return bestPage;
    }

    // 優先序 3: 若 AI 原始標註了頁碼
    if (aiSuggestedPage != null && aiSuggestedPage >= 1 && aiSuggestedPage <= pages.length) {
      return aiSuggestedPage;
    }

    // 優先序 4: 任何非目錄且出現該詞的第一個頁面
    for (final p in pagesWithOccurrences) {
      if (p > 1 || !page1IsTOC) {
        return p;
      }
    }

    return pagesWithOccurrences.isNotEmpty ? pagesWithOccurrences.first : 1;
  }

  /// 校準標籤清單的頁碼（pageNumber 與 pages），修正目錄判斷誤導
  static List<TagItem> calibrateTags({
    required List<TagItem> tags,
    required List<PageItem> pages,
    String? title,
  }) {
    if (pages.isEmpty) return tags;
    if (pages.length == 1) {
      return tags.map((t) => t.copyWith(pageNumber: 1, pages: [1])).toList();
    }

    final calibrated = <TagItem>[];

    for (final tag in tags) {
      final substantivePage = findSubstantivePageForKeyword(
        tag.name,
        pages,
        aiSuggestedPage: tag.pageNumber,
      );

      // 收集該標籤在所有頁面出現的清單
      final normName = TextNormalizer.normalizeTag(tag.name).toLowerCase();
      final allPagesWithTag = <int>[];

      for (final p in pages) {
        if (p.ocrText.toLowerCase().contains(normName)) {
          allPagesWithTag.add(p.pageNumber);
        }
      }

      if (substantivePage != null && !allPagesWithTag.contains(substantivePage)) {
        allPagesWithTag.add(substantivePage);
        allPagesWithTag.sort();
      }

      calibrated.add(tag.copyWith(
        pageNumber: substantivePage,
        pages: allPagesWithTag.isNotEmpty ? allPagesWithTag : (substantivePage != null ? [substantivePage] : null),
      ));
    }

    return calibrated;
  }

  /// 為檢索結果計算最佳實質命中頁碼，優先使用標籤的精確頁數，並避免僅以第 1 頁目錄判斷
  static int? resolveSubstantivePageForSearchHit({
    required List<String> searchKeywords,
    required List<String> searchTags,
    required List<TagItem> docTags,
    required List<PageItem> docPages,
    String? docSummary,
  }) {
    // 1. 若查詢包含標籤，或關鍵字正好命中已校準之標籤，優先使用標籤於原始文獻中紀錄的正確頁碼
    final allSearchTerms = [...searchTags, ...searchKeywords].map((s) => s.toLowerCase()).toSet();

    for (final tag in docTags) {
      if (tag.pageNumber != null && tag.pageNumber! > 0) {
        final normTag = tag.name.toLowerCase();
        if (allSearchTerms.contains(normTag) ||
            allSearchTerms.any((term) => term.isNotEmpty && (normTag.contains(term) || term.contains(normTag)))) {
          return tag.pageNumber;
        }
      }
    }

    // 2. 若為關鍵字檢索，使用防目錄誤導演算法計算實質內文頁數
    if (searchKeywords.isNotEmpty && docPages.isNotEmpty) {
      for (final kw in searchKeywords) {
        final page = findSubstantivePageForKeyword(kw, docPages);
        if (page != null && page > 0) {
          return page;
        }
      }
    }

    // 3. 檢查摘要引註頁碼 (P.X) 或 第 X 頁
    if (docSummary != null && docSummary.isNotEmpty) {
      final pageRegex = RegExp(r'(?:P\.?\s*([0-9]+)|第\s*([0-9]+)\s*頁|【(?:P\.?\s*|第\s*)([0-9]+))', caseSensitive: false);
      final match = pageRegex.firstMatch(docSummary);
      if (match != null) {
        final p = int.tryParse(match.group(1) ?? match.group(2) ?? match.group(3) ?? '');
        if (p != null && p >= 1) {
          return p;
        }
      }
    }

    // 4. 若僅有單一頁面，回傳該頁之頁碼
    if (docPages.length == 1) {
      return docPages.first.pageNumber;
    }

    return null;
  }
}
