import 'package:flutter/material.dart';

/// Rendu léger d'un texte pouvant contenir une mise en forme HTML simple
/// (produite par l'éditeur visuel du site) : gras, italique, souligné,
/// couleur, retours à la ligne et listes à puces.
///
/// L'appli ne permet pas *d'éditer* le HTML — seulement de l'afficher — mais un
/// texte brut (sans balise) reste rendu tel quel. Volontairement minimaliste :
/// pas de dépendance externe.
class RichTextView extends StatelessWidget {
  final String? raw;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign textAlign;

  const RichTextView(
    this.raw, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign = TextAlign.start,
  });

  static bool looksLikeHtml(String? s) =>
      s != null && RegExp(r'<(/?)(b|strong|i|em|u|span|font|p|div|br|ul|ol|li)\b',
              caseSensitive: false)
          .hasMatch(s);

  @override
  Widget build(BuildContext context) {
    final text = raw ?? '';
    // Galey n'a qu'une graisse (semibold) → gras/italique invisibles. Le contenu
    // éducateur est rendu en NotoSans (vrai gras + italique), quel que soit le
    // style passé par l'appelant.
    final base = (style ?? const TextStyle(fontSize: 13, color: Color(0xFF444444)))
        .copyWith(fontFamily: 'NotoSans');
    if (!looksLikeHtml(text)) {
      return Text(text,
          style: base,
          maxLines: maxLines,
          overflow: overflow ?? TextOverflow.clip,
          textAlign: textAlign);
    }
    return Text.rich(
      TextSpan(children: parseRichText(text, base)),
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
      textAlign: textAlign,
    );
  }
}

/// Texte nu d'un fragment HTML simple (pour pré-remplir un éditeur brut).
String richTextToPlain(String? input) {
  final s = input ?? '';
  if (!RichTextView.looksLikeHtml(s)) return s;
  var out = s
      .replaceAll(RegExp(r'<\s*br\s*/?\s*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</\s*(p|div|li)\s*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '');
  return _unescape(out).replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}

/// Convertit un fragment HTML simple en `InlineSpan`s.
List<InlineSpan> parseRichText(String input, TextStyle baseStyle) {
  // 1. Normalise les balises de bloc en sauts de ligne / puces.
  var s = input
      .replaceAll(RegExp(r'<\s*br\s*/?\s*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<\s*li[^>]*>', caseSensitive: false), '• ')
      .replaceAll(RegExp(r'</\s*li\s*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</\s*(p|div)\s*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<\s*(p|div)[^>]*>', caseSensitive: false), '')
      .replaceAll(RegExp(r'</?\s*(ul|ol)[^>]*>', caseSensitive: false), '');

  final spans = <InlineSpan>[];
  final styleStack = <TextStyle>[baseStyle];
  final tagRe = RegExp(
      r'<(/?)(b|strong|i|em|u|span|font)((?:\s+[^>]*?)?)\s*>',
      caseSensitive: false);

  var cursor = 0;
  for (final m in tagRe.allMatches(s)) {
    if (m.start > cursor) {
      final chunk = _unescape(s.substring(cursor, m.start));
      if (chunk.isNotEmpty) {
        spans.add(TextSpan(text: chunk, style: styleStack.last));
      }
    }
    final closing = m.group(1) == '/';
    final tag = m.group(2)!.toLowerCase();
    final attrs = m.group(3) ?? '';
    if (closing) {
      if (styleStack.length > 1) styleStack.removeLast();
    } else {
      var next = styleStack.last;
      switch (tag) {
        case 'b':
        case 'strong':
          next = next.copyWith(fontWeight: FontWeight.w700);
          break;
        case 'i':
        case 'em':
          next = next.copyWith(fontStyle: FontStyle.italic);
          break;
        case 'u':
          next = next.copyWith(decoration: TextDecoration.underline);
          break;
        case 'span':
          final col = _colorFromStyle(attrs);
          if (col != null) next = next.copyWith(color: col);
          if (RegExp(r'font-weight\s*:\s*(bold|[6-9]00)', caseSensitive: false).hasMatch(attrs)) {
            next = next.copyWith(fontWeight: FontWeight.w700);
          }
          if (RegExp(r'font-style\s*:\s*italic', caseSensitive: false).hasMatch(attrs)) {
            next = next.copyWith(fontStyle: FontStyle.italic);
          }
          if (RegExp(r'text-decoration[^;"]*underline', caseSensitive: false).hasMatch(attrs)) {
            next = next.copyWith(decoration: TextDecoration.underline);
          }
          break;
        case 'font':
          final col = _colorFromStyle(attrs) ?? _colorFromFontAttr(attrs);
          if (col != null) next = next.copyWith(color: col);
          break;
      }
      styleStack.add(next);
    }
    cursor = m.end;
  }
  if (cursor < s.length) {
    final chunk = _unescape(s.substring(cursor));
    if (chunk.isNotEmpty) spans.add(TextSpan(text: chunk, style: styleStack.last));
  }
  return spans;
}

Color? _colorFromFontAttr(String attrs) {
  final m = RegExp(r'''color\s*=\s*["']?(#[0-9a-fA-F]{3,8}|rgba?\([^)]*\))''',
          caseSensitive: false)
      .firstMatch(attrs);
  return m == null ? null : _parseCssColor(m.group(1)!.trim());
}

Color? _colorFromStyle(String attrs) {
  final m = RegExp(r'color\s*:\s*(#[0-9a-fA-F]{3,8}|rgba?\([^)]*\))',
          caseSensitive: false)
      .firstMatch(attrs);
  return m == null ? null : _parseCssColor(m.group(1)!.trim());
}

Color? _parseCssColor(String v) {
  if (v.startsWith('#')) {
    var hex = v.substring(1);
    if (hex.length == 3) hex = hex.split('').map((c) => '$c$c').join();
    if (hex.length == 6) hex = 'FF$hex';
    if (hex.length == 8) {
      final n = int.tryParse(hex, radix: 16);
      if (n != null) return Color(n);
    }
    return null;
  }
  final nums = RegExp(r'[\d.]+')
      .allMatches(v)
      .map((x) => x.group(0)!)
      .toList();
  if (nums.length >= 3) {
    final r = int.tryParse(nums[0]) ?? 0;
    final g = int.tryParse(nums[1]) ?? 0;
    final b = int.tryParse(nums[2]) ?? 0;
    final a = nums.length >= 4 ? ((double.tryParse(nums[3]) ?? 1) * 255).round() : 255;
    return Color.fromARGB(a, r, g, b);
  }
  return null;
}

String _unescape(String s) => s
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&apos;', "'");
