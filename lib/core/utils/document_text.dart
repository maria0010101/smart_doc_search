/// Reflows extraction line breaks without modifying stored OCR or copied text.
class DocumentText {
  DocumentText._();

  static final _lineBreak = RegExp(r'[ \t]*\n[ \t]*');
  static final _hanBoundary = RegExp(
    r'([\u3400-\u9fff\uf900-\ufaff])[ \t]*\n[ \t]*(?=[\u3400-\u9fff\uf900-\ufaff])',
  );

  /// Blank lines remain paragraph boundaries; extracted short lines reflow.
  static String reflow(String text) => text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split(RegExp(r'\n[ \t]*\n+'))
      .map(
        (paragraph) => paragraph
            .replaceAllMapped(_hanBoundary, (m) => m.group(1)!)
            .replaceAll(_lineBreak, ' '),
      )
      .join('\n\n');

  /// Search text with original casing, suitable for context snippets.
  static String searchContent(String text) =>
      reflow(text.replaceAll(RegExp(r'[\r\n]+'), '\n'))
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

  /// Case-insensitive search ignores extraction line breaks and repeated spaces.
  static String searchable(String text) => searchContent(text).toLowerCase();
}
