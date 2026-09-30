/// Search-engine style query operators for document search.
///
/// Supported syntax (matching the behaviour of common search engines):
///  * `A+B`  — the `+` connector requires **all** joined keywords to appear
///              (AND semantics), e.g. `糖尿病+心血管`.
///  * `+A`   — a leading `+` marks a single required keyword.
///  * `-A`   — a leading `-` marks an excluded keyword; any document whose
///              text contains it is removed from the result set,
///              e.g. `糖尿病 -動物實驗`.
///  * `A B`  — space separated keywords stay optional and only contribute to
///              relevance scoring (OR semantics, ranked by score).
///
/// Hyphens that belong to a term (`COVID-19`, `IL-6`, `T-cell`) and hyphens
/// sitting between two Han characters are disambiguated automatically: a hyphen
/// acts as the exclusion operator only when it starts a keyword, when it sits
/// between two Han characters, or when the same token also uses `+`.
library;

/// Parsed representation of a user query, split into the three keyword groups.
class ParsedSearchQuery {
  /// Keywords that must all be present in a matching document (AND group).
  final List<String> required;

  /// Keywords that only contribute to relevance (OR / optional group).
  final List<String> optional;

  /// Keywords that must not be present in a matching document.
  final List<String> excluded;

  const ParsedSearchQuery({
    this.required = const <String>[],
    this.optional = const <String>[],
    this.excluded = const <String>[],
  });

  bool get isEmpty => required.isEmpty && optional.isEmpty && excluded.isEmpty;

  bool get hasOperators => required.isNotEmpty || excluded.isNotEmpty;

  /// Positive keywords used for scoring, snippet extraction and page calibration.
  List<String> get positiveKeywords => <String>[...required, ...optional];

  /// Keywords encoded with operator prefixes, understood by every data source:
  /// `+term` required, `-term` excluded, `term` optional.
  List<String> toEncodedKeywords() => <String>[
        ...required.map((t) => '+$t'),
        ...optional,
        ...excluded.map((t) => '-$t'),
      ];

  /// Short human readable hint describing the parsed operators (for the UI).
  String get operatorSummary {
    final parts = <String>[];
    if (required.isNotEmpty) parts.add('必須包含：${required.join('、')}');
    if (excluded.isNotEmpty) parts.add('排除：${excluded.join('、')}');
    return parts.join('　｜　');
  }
}

/// Splits an operator-annotated query string into required / optional / excluded
/// keyword groups and decodes the operator-prefixed keyword list exchanged with
/// the storage engines.
class SearchQueryParser {
  SearchQueryParser._();

  static bool _isHan(int codeUnit) =>
      (codeUnit >= 0x3400 && codeUnit <= 0x4DBF) ||
      (codeUnit >= 0x4E00 && codeUnit <= 0x9FFF) ||
      (codeUnit >= 0xF900 && codeUnit <= 0xFAFF);

  static ParsedSearchQuery parse(String raw) {
    final required = <String>[];
    final optional = <String>[];
    final excluded = <String>[];

    for (final token in raw.split(RegExp(r'\s+'))) {
      if (token.isEmpty) continue;
      for (final segment in _splitToken(token)) {
        final term = segment.$2;
        if (term.isEmpty) continue;
        switch (segment.$1) {
          case '+':
            required.add(term);
            break;
          case '-':
            excluded.add(term);
            break;
          default:
            optional.add(term);
        }
      }
    }

    // A term must never live in two groups; exclusion always wins.
    final excludedFinal = _dedupe(excluded);
    final excludedLower = excludedFinal.map((e) => e.toLowerCase()).toSet();
    final requiredFinal = _dedupe(required)
        .where((t) => !excludedLower.contains(t.toLowerCase()))
        .toList();
    final requiredLower = requiredFinal.map((e) => e.toLowerCase()).toSet();
    final optionalFinal = _dedupe(optional)
        .where((t) =>
            !excludedLower.contains(t.toLowerCase()) &&
            !requiredLower.contains(t.toLowerCase()))
        .toList();

    return ParsedSearchQuery(
      required: requiredFinal,
      optional: optionalFinal,
      excluded: excludedFinal,
    );
  }

  static List<String> _dedupe(List<String> items) {
    final seen = <String>{};
    final out = <String>[];
    for (final item in items) {
      if (seen.add(item.toLowerCase())) out.add(item);
    }
    return out;
  }

  /// Splits a whitespace token into `(operator, term)` segments.
  static List<(String, String)> _splitToken(String token) {
    final out = <(String, String)>[];
    final buffer = StringBuffer();
    var op = '';
    final mixedOperators = token.contains('+') && token.contains('-');

    void flush() {
      final term = buffer.toString().trim();
      buffer.clear();
      if (term.isNotEmpty) out.add((op, term));
      op = '';
    }

    final units = token.runes.toList();
    for (var i = 0; i < units.length; i++) {
      final ch = String.fromCharCode(units[i]);
      if (ch == '+' && i < units.length - 1) {
        if (op.isEmpty) op = '+';
        flush();
        op = '+';
        continue;
      }
      if (ch == '-') {
        final prev = i > 0 ? units[i - 1] : -1;
        final next = i + 1 < units.length ? units[i + 1] : -1;
        final leading = i == 0;
        final betweenHan = prev > 0 && next > 0 && _isHan(prev) && _isHan(next);
        if (leading || betweenHan || mixedOperators) {
          flush();
          op = '-';
          continue;
        }
      }
      buffer.writeCharCode(units[i]);
    }
    flush();
    return out;
  }
}

/// Decoded operator-prefixed keyword list received by a storage engine.
class EncodedKeywordSet {
  final List<String> required;
  final List<String> optional;
  final List<String> excluded;

  const EncodedKeywordSet({
    this.required = const <String>[],
    this.optional = const <String>[],
    this.excluded = const <String>[],
  });

  /// All positive (required + optional) keywords used for scoring.
  List<String> get positive => <String>[...required, ...optional];

  bool get hasAnyPositive => required.isNotEmpty || optional.isNotEmpty;

  /// True when [haystack] (already lower-cased) satisfies the AND / NOT gates.
  bool matchesGates(String haystackLower) {
    for (final term in required) {
      if (!haystackLower.contains(term.toLowerCase())) return false;
    }
    for (final term in excluded) {
      if (haystackLower.contains(term.toLowerCase())) return false;
    }
    return true;
  }

  /// Decodes `+term` / `-term` / `term` entries emitted by
  /// [ParsedSearchQuery.toEncodedKeywords].
  factory EncodedKeywordSet.fromEncoded(List<String> encoded) {
    final required = <String>[];
    final optional = <String>[];
    final excluded = <String>[];

    for (final rawEntry in encoded) {
      final entry = rawEntry.trim();
      if (entry.isEmpty) continue;
      if (entry.startsWith('-') && entry.length > 1) {
        excluded.add(entry.substring(1).trim());
      } else if (entry.startsWith('+') && entry.length > 1) {
        required.add(entry.substring(1).trim());
      } else {
        optional.add(entry);
      }
    }

    return EncodedKeywordSet(
      required: required.where((e) => e.isNotEmpty).toList(),
      optional: optional.where((e) => e.isNotEmpty).toList(),
      excluded: excluded.where((e) => e.isNotEmpty).toList(),
    );
  }
}
