import 'package:flutter/material.dart';

import 'format_range.dart';

/// Plain text + optional span runs → [TextSpan] tree for display/editing.
class TextSpanBuilder {
  static TextSpan build({
    required String text,
    required TextStyle baseStyle,
    List<dynamic>? spans,
  }) {
    final normalized = normalizeSpans(spans, text.length);
    if (normalized.isEmpty) {
      return TextSpan(text: text, style: baseStyle);
    }
    final children = <InlineSpan>[];
    var cursor = 0;
    for (final span in normalized) {
      final start = span['start'] as int;
      final end = span['end'] as int;
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

List<Map<String, dynamic>> parseSpans(Map<String, dynamic> content) {
  final raw = content['spans'];
  if (raw is! List) return [];
  return [
    for (final item in raw)
      if (item is Map) Map<String, dynamic>.from(item),
  ];
}

/// Load text + spans from block content (including legacy parchment delta).
({String text, List<Map<String, dynamic>> spans}) richContentFromBlock(
  Map<String, dynamic> content,
) {
  final existingSpans = parseSpans(content);
  var text = content['text']?.toString() ?? '';

  if (existingSpans.isNotEmpty) {
    return (text: text, spans: existingSpans);
  }

  final parchment = content['parchment'];
  if (parchment is List && parchment.isNotEmpty) {
    final migrated = _richContentFromParchment(parchment);
    return (text: migrated.text, spans: migrated.spans);
  }

  return (text: text, spans: existingSpans);
}

({String text, List<Map<String, dynamic>> spans}) _richContentFromParchment(
  List<dynamic> ops,
) {
  final buffer = StringBuffer();
  final spans = <Map<String, dynamic>>[];
  var offset = 0;

  for (final raw in ops) {
    if (raw is! Map) continue;
    final insert = raw['insert'];
    if (insert is! String || insert.isEmpty) continue;

    final attrs = raw['attributes'];
    final style = attrs is Map ? _spanStyleFromParchment(attrs) : null;
    final start = offset;
    buffer.write(insert);
    offset += insert.length;

    if (style != null && _spanHasStyle(style)) {
      spans.add({...style, 'start': start, 'end': offset});
    }
  }

  var text = buffer.toString();
  if (text.endsWith('\n')) {
    final trimEnd = text.length - 1;
    text = text.substring(0, trimEnd);
    for (final span in spans) {
      final end = span['end'] as int;
      if (end > trimEnd) span['end'] = trimEnd;
    }
  }

  return (
    text: text,
    spans: coalesceSpans(
      spans.where((s) => (s['end'] as int) > (s['start'] as int)).toList(),
    ),
  );
}

Map<String, dynamic> _spanStyleFromParchment(Map<dynamic, dynamic> attrs) {
  final span = <String, dynamic>{};
  if (attrs['b'] == true) span['bold'] = true;
  if (attrs['i'] == true) span['italic'] = true;
  if (attrs['u'] == true) span['underline'] = true;
  return span;
}

Map<String, dynamic> spanContentPatch(
  Map<String, dynamic> base,
  String text,
  List<Map<String, dynamic>> spans,
) {
  return {
    ...base,
    'text': text,
    'spans': spans,
    'compose_style': null,
    'parchment': null,
    'text_style': null,
  };
}

List<Map<String, dynamic>> normalizeSpans(
  List<dynamic>? spans,
  int textLength,
) {
  if (spans == null || spans.isEmpty) return [];
  final cleaned = <Map<String, dynamic>>[];
  for (final raw in spans) {
    if (raw is! Map) continue;
    final span = Map<String, dynamic>.from(raw);
    final start = (span['start'] as int? ?? 0).clamp(0, textLength);
    final end = (span['end'] as int? ?? 0).clamp(0, textLength);
    if (end <= start) continue;
    if (!_spanHasStyle(span)) continue;
    cleaned.add({...span, 'start': start, 'end': end});
  }
  cleaned.sort((a, b) => (a['start'] as int).compareTo(b['start'] as int));
  return cleaned;
}

bool _spanHasStyle(Map<String, dynamic> span) {
  return span['bold'] == true ||
      span['italic'] == true ||
      span['underline'] == true ||
      span['size'] is num ||
      (span['color'] is String && (span['color'] as String).isNotEmpty);
}

/// Per-character span remap after a text edit.
///
/// Inserted characters are unstyled unless the insertion point lies **inside**
/// a styled span (`start <= index < end`). Inserting at `index == span.end` does
/// not extend the style — this prevents bold "dragging" onto text typed after a
/// formatted word.
List<Map<String, dynamic>> remapSpansForTextEdit(
  List<Map<String, dynamic>> spans,
  String oldText,
  String newText,
) {
  if (oldText == newText) return spans;

  final diff = textEditDiff(oldText, newText);
  final oldMarks = _marksForText(oldText, spans);
  final newMarks = <Map<String, dynamic>>[];

  for (var i = 0; i < diff.replaceStart; i++) {
    newMarks.add(_copyMark(oldMarks[i]));
  }

  final removedStyle = diff.removedLength > 0
      ? _uniformMarkInRange(
          oldMarks,
          diff.replaceStart,
          diff.removedLength,
        )
      : const <String, dynamic>{};

  for (var k = 0; k < diff.insertedLength; k++) {
    if (diff.removedLength > 0) {
      newMarks.add(_copyMark(removedStyle));
    } else {
      final inherit = _markAtInsertPoint(spans, diff.replaceStart);
      newMarks.add(_copyMark(inherit ?? const {}));
    }
  }

  final tailStart = diff.replaceStart + diff.removedLength;
  for (var i = tailStart; i < oldMarks.length; i++) {
    newMarks.add(_copyMark(oldMarks[i]));
  }

  return _spansFromMarks(newMarks, newText.length);
}

List<Map<String, dynamic>> _marksForText(
  String text,
  List<Map<String, dynamic>> spans,
) =>
    _marksForLength(text.length, spans);

List<Map<String, dynamic>> _marksForLength(
  int textLength,
  List<Map<String, dynamic>> spans,
) {
  final marks = List<Map<String, dynamic>>.generate(
    textLength,
    (_) => <String, dynamic>{},
  );
  for (final span in normalizeSpans(spans, textLength)) {
    final style = _markFromSpan(span);
    if (style.isEmpty) continue;
    final start = span['start'] as int;
    final end = span['end'] as int;
    for (var i = start; i < end; i++) {
      marks[i] = _copyMark(style);
    }
  }
  return marks;
}

Map<String, dynamic> _markFromSpan(Map<String, dynamic> span) {
  final mark = <String, dynamic>{};
  if (span['bold'] == true) mark['bold'] = true;
  if (span['italic'] == true) mark['italic'] = true;
  if (span['underline'] == true) mark['underline'] = true;
  if (span['size'] is num) mark['size'] = span['size'];
  if (span['color'] is String) mark['color'] = span['color'];
  return mark;
}

Map<String, dynamic> _copyMark(Map<String, dynamic> mark) =>
    Map<String, dynamic>.from(mark);

Map<String, dynamic>? _markAtInsertPoint(
  List<Map<String, dynamic>> spans,
  int index,
) {
  for (final span in spans) {
    final start = span['start'] as int;
    final end = span['end'] as int;
    if (start <= index && index < end) {
      return _markFromSpan(span);
    }
  }
  return null;
}

Map<String, dynamic> _uniformMarkInRange(
  List<Map<String, dynamic>> marks,
  int start,
  int length,
) {
  if (length <= 0) return {};
  final first = marks[start];
  for (var i = start + 1; i < start + length; i++) {
    if (!_marksEqual(first, marks[i])) return {};
  }
  return _copyMark(first);
}

bool _marksEqual(Map<String, dynamic> a, Map<String, dynamic> b) {
  return a['bold'] == b['bold'] &&
      a['italic'] == b['italic'] &&
      a['underline'] == b['underline'] &&
      a['size'] == b['size'] &&
      a['color'] == b['color'];
}

List<Map<String, dynamic>> _spansFromMarks(
  List<Map<String, dynamic>> marks,
  int textLength,
) {
  if (textLength == 0 || marks.isEmpty) return [];
  final spans = <Map<String, dynamic>>[];
  var runStart = 0;
  var runMark = _copyMark(marks[0]);

  for (var i = 1; i < marks.length; i++) {
    if (!_marksEqual(runMark, marks[i])) {
      if (runMark.isNotEmpty) {
        spans.add({...runMark, 'start': runStart, 'end': i});
      }
      runStart = i;
      runMark = _copyMark(marks[i]);
    }
  }
  if (runMark.isNotEmpty) {
    spans.add({...runMark, 'start': runStart, 'end': marks.length});
  }
  return normalizeSpans(spans, textLength);
}

/// Adjust span offsets after a text edit. Inserts at [start] replace
/// `removedLength` characters with `insertedLength` new ones.
///
/// **Invariant:** insertion exactly at `spanEnd` (`spanEnd == start`,
/// nothing removed) must NOT extend the span — use strict `spanEnd < start`.
List<Map<String, dynamic>> shiftSpansForEdit(
  List<Map<String, dynamic>> spans, {
  required int start,
  required int removedLength,
  required int insertedLength,
  required int textLength,
}) {
  final delta = insertedLength - removedLength;
  final removeEnd = start + removedLength;
  final next = <Map<String, dynamic>>[];

  for (final span in spans) {
    final spanStart = span['start'] as int;
    final spanEnd = span['end'] as int;

    if (spanEnd < start || spanStart >= removeEnd) {
      next.add({
        ...span,
        'start': spanStart + delta,
        'end': spanEnd + delta,
      });
      continue;
    }

    final beforeEnd = spanStart < start ? start : spanStart;
    final afterStart = spanEnd > removeEnd ? removeEnd : spanEnd;
    if (spanStart < start) {
      next.add({...span, 'start': spanStart, 'end': beforeEnd});
    }
    if (spanEnd > removeEnd) {
      next.add({
        ...span,
        'start': afterStart + delta,
        'end': spanEnd + delta,
      });
    }
  }

  return normalizeSpans(spans, textLength);
}

class TextEditDiff {
  const TextEditDiff({
    required this.replaceStart,
    required this.removedLength,
    required this.insertedLength,
  });

  final int replaceStart;
  final int removedLength;
  final int insertedLength;
}

TextEditDiff textEditDiff(String oldText, String newText) {
  var prefix = 0;
  final maxPrefix = oldText.length < newText.length ? oldText.length : newText.length;
  while (prefix < maxPrefix && oldText[prefix] == newText[prefix]) {
    prefix++;
  }

  var oldSuffix = oldText.length;
  var newSuffix = newText.length;
  while (oldSuffix > prefix &&
      newSuffix > prefix &&
      oldText[oldSuffix - 1] == newText[newSuffix - 1]) {
    oldSuffix--;
    newSuffix--;
  }

  return TextEditDiff(
    replaceStart: prefix,
    removedLength: oldSuffix - prefix,
    insertedLength: newSuffix - prefix,
  );
}

List<Map<String, dynamic>> applyStyleToRange(
  List<Map<String, dynamic>> spans, {
  required int start,
  required int end,
  required Map<String, dynamic> style,
  bool merge = false,
}) {
  if (end <= start) return spans;
  final styleKeys = style.keys.where((k) => k != 'start' && k != 'end').toList();
  if (styleKeys.isEmpty) return spans;

  final patched = <Map<String, dynamic>>[];
  for (final span in spans) {
    final spanStart = span['start'] as int;
    final spanEnd = span['end'] as int;
    if (spanEnd <= start || spanStart >= end) {
      patched.add(span);
      continue;
    }
    if (spanStart < start) {
      patched.add({...span, 'start': spanStart, 'end': start});
    }
    if (spanEnd > end) {
      patched.add({...span, 'start': end, 'end': spanEnd});
    }
  }

  final applied = <String, dynamic>{'start': start, 'end': end};
  for (final key in styleKeys) {
    if (style[key] != null) applied[key] = style[key];
  }
  patched.add(applied);
  return coalesceSpans(patched);
}

/// Mutates a single style property on one character mark.
void applyActionToMark(
  Map<String, dynamic> mark,
  String action,
  double baseFontSize,
) {
  switch (action) {
    case 'text:bold':
      if (mark['bold'] == true) {
        mark.remove('bold');
      } else {
        mark['bold'] = true;
      }
    case 'text:italic':
      if (mark['italic'] == true) {
        mark.remove('italic');
      } else {
        mark['italic'] = true;
      }
    case 'text:underline':
      if (mark['underline'] == true) {
        mark.remove('underline');
      } else {
        mark['underline'] = true;
      }
    case 'text:size_up':
      final current = (mark['size'] as num?)?.toDouble() ?? baseFontSize;
      final next = current + 1;
      if (next == baseFontSize) {
        mark.remove('size');
      } else {
        mark['size'] = next;
      }
    case 'text:size_down':
      final current = (mark['size'] as num?)?.toDouble() ?? baseFontSize;
      final next = (current - 1).clamp(10.0, 48.0);
      if (next == baseFontSize) {
        mark.remove('size');
      } else {
        mark['size'] = next;
      }
  }
}

List<Map<String, dynamic>> applyFormatActionToRange(
  List<Map<String, dynamic>> spans, {
  required int start,
  required int end,
  required int textLength,
  required String action,
  required double baseFontSize,
}) {
  if (end <= start) return spans;

  final clampedStart = start.clamp(0, textLength);
  final clampedEnd = end.clamp(0, textLength);
  if (clampedEnd <= clampedStart) return spans;

  final marks = _marksForLength(textLength, spans);
  for (var i = clampedStart; i < clampedEnd; i++) {
    applyActionToMark(marks[i], action, baseFontSize);
  }
  return _spansFromMarks(marks, textLength);
}

Map<String, dynamic> styleForRange(
  List<Map<String, dynamic>> spans,
  int start,
  int end,
  double baseFontSize,
) {
  final merged = <String, dynamic>{'size': baseFontSize};
  for (final span in spans) {
    final spanStart = span['start'] as int;
    final spanEnd = span['end'] as int;
    if (spanEnd <= start || spanStart >= end) continue;
    if (span['bold'] == true) merged['bold'] = true;
    if (span['italic'] == true) merged['italic'] = true;
    if (span['underline'] == true) merged['underline'] = true;
    if (span['size'] is num) merged['size'] = span['size'];
  }
  return merged;
}

List<Map<String, dynamic>> coalesceSpans(List<Map<String, dynamic>> spans) {
  if (spans.isEmpty) return [];
  final sorted = [...spans]
    ..sort((a, b) => (a['start'] as int).compareTo(b['start'] as int));
  final merged = <Map<String, dynamic>>[];
  for (final span in sorted) {
    if (merged.isEmpty) {
      merged.add(span);
      continue;
    }
    final prev = merged.last;
    if (_sameStyle(prev, span) && (prev['end'] as int) == (span['start'] as int)) {
      prev['end'] = span['end'];
    } else {
      merged.add(span);
    }
  }
  return merged;
}

bool _sameStyle(Map<String, dynamic> a, Map<String, dynamic> b) {
  return a['bold'] == b['bold'] &&
      a['italic'] == b['italic'] &&
      a['underline'] == b['underline'] &&
      a['size'] == b['size'] &&
      a['color'] == b['color'];
}

Map<String, dynamic> applyTextFormatToContent({
  required Map<String, dynamic> content,
  required String action,
  required TextSelection selection,
  required String text,
  required double baseFontSize,
}) {
  final spans = parseSpans(content);
  if (!selection.isValid) return content;

  final range = FormatRange.resolve(text, selection);
  if (!range.isValid) return content;

  final start = range.start;
  final end = range.end;
  final nextSpans = applyFormatActionToRange(
    spans,
    start: start,
    end: end,
    textLength: text.length,
    action: action,
    baseFontSize: baseFontSize,
  );
  return {
    ...content,
    'text': text,
    'spans': nextSpans,
    'compose_style': null,
  };
}
