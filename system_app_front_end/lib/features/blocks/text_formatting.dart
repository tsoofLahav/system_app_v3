import 'package:flutter/material.dart';

/// Plain text + optional span runs → [TextSpan] tree for display.
class TextSpanBuilder {
  static TextSpan build({
    required String text,
    required TextStyle baseStyle,
    List<dynamic>? spans,
  }) {
    if (spans == null || spans.isEmpty) {
      return TextSpan(text: text, style: baseStyle);
    }
    final children = <InlineSpan>[];
    var cursor = 0;
    final sorted = List<Map<String, dynamic>>.from(
      spans.map((e) => Map<String, dynamic>.from(e as Map)),
    )..sort((a, b) => (a['start'] as int).compareTo(b['start'] as int));

    for (final span in sorted) {
      final start = span['start'] as int? ?? 0;
      final end = span['end'] as int? ?? 0;
      if (start > cursor) {
        children.add(TextSpan(text: text.substring(cursor, start), style: baseStyle));
      }
      if (end > start && end <= text.length) {
        children.add(TextSpan(
          text: text.substring(start, end),
          style: _styleForSpan(baseStyle, span),
        ));
        cursor = end;
      }
    }
    if (cursor < text.length) {
      children.add(TextSpan(text: text.substring(cursor), style: baseStyle));
    }
    return TextSpan(children: children);
  }

  static TextStyle _styleForSpan(TextStyle base, Map<String, dynamic> span) {
    var style = base;
    if (span['bold'] == true) style = style.copyWith(fontWeight: FontWeight.w600);
    if (span['italic'] == true) style = style.copyWith(fontStyle: FontStyle.italic);
    if (span['underline'] == true) {
      style = style.copyWith(decoration: TextDecoration.underline);
    }
    final size = span['size'];
    if (size is num) style = style.copyWith(fontSize: size.toDouble());
    final color = span['color'];
    if (color is String && color.startsWith('#')) {
      final hex = color.substring(1);
      if (hex.length == 6) {
        style = style.copyWith(
          color: Color(int.parse('FF$hex', radix: 16)),
        );
      }
    }
    return style;
  }
}

/// Applies or toggles a whole-block text_style map (incremental spans migration).
Map<String, dynamic> toggleTextStyle(
  Map<String, dynamic> content,
  String key,
) {
  final style = Map<String, dynamic>.from(
    (content['text_style'] as Map?)?.cast<String, dynamic>() ?? {},
  );
  style[key] = !(style[key] == true);
  return {...content, 'text_style': style};
}

TextStyle applyBlockTextStyle(TextStyle base, Map<String, dynamic>? content) {
  final style = content?['text_style'] as Map?;
  if (style == null) return base;
  var result = base;
  if (style['bold'] == true) result = result.copyWith(fontWeight: FontWeight.w600);
  if (style['italic'] == true) result = result.copyWith(fontStyle: FontStyle.italic);
  if (style['underline'] == true) {
    result = result.copyWith(decoration: TextDecoration.underline);
  }
  final size = style['size'];
  if (size is num) result = result.copyWith(fontSize: size.toDouble());
  return result;
}
