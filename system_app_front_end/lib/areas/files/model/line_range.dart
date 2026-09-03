import 'package:flutter/material.dart';

import '../../../shared/utils/platform_text.dart';

/// Character range for the current selection or caret line (until newline).
class LineRange {
  const LineRange({required this.start, required this.end});

  final int start;
  final int end;

  bool get isValid => end > start;

  TextSelection get selection =>
      TextSelection(baseOffset: start, extentOffset: end);

  /// Highlighted text, or the line at the caret when nothing is marked.
  static LineRange resolve(String text, TextSelection selection) {
    if (!selection.isValid) {
      return const LineRange(start: 0, end: 0);
    }

    if (!selection.isCollapsed) {
      final (start, end) = normalizeUtf16Range(
        text,
        selection.start,
        selection.end,
      );
      if (end > start) {
        return LineRange(start: start, end: end);
      }
    }

    final caret = selection.baseOffset.clamp(0, text.length);
    final lineStart = caret == 0 ? 0 : text.lastIndexOf('\n', caret - 1) + 1;
    final nextNewline = text.indexOf('\n', caret);
    final lineEnd = nextNewline == -1 ? text.length : nextNewline;

    if (lineEnd <= lineStart) {
      return LineRange(start: caret, end: caret);
    }
    return LineRange(start: lineStart, end: lineEnd);
  }

  /// Flutter word / line select often includes a trailing `\n`. In RTL that
  /// paints a highlight across the empty rest of the line. Super Editor does
  /// not. Internal newlines (a multi-line mark) stay.
  static TextSelection withoutEdgeNewlines(
    String text,
    TextSelection selection,
  ) {
    if (!selection.isValid || selection.isCollapsed) return selection;
    var start = selection.start.clamp(0, text.length);
    var end = selection.end.clamp(0, text.length);
    if (end < start) {
      final swap = start;
      start = end;
      end = swap;
    }
    while (start < end && _isNewline(text.codeUnitAt(start))) {
      start++;
    }
    while (end > start && _isNewline(text.codeUnitAt(end - 1))) {
      end--;
    }
    if (start == selection.start && end == selection.end) return selection;
    if (start >= end) {
      return TextSelection.collapsed(offset: selection.extentOffset);
    }
    if (selection.baseOffset <= selection.extentOffset) {
      return TextSelection(baseOffset: start, extentOffset: end);
    }
    return TextSelection(baseOffset: end, extentOffset: start);
  }

  static bool _isNewline(int unit) => unit == 0x0A || unit == 0x0D;
}

/// Word under [offset] for a phone double-tap mark (Hebrew and Latin).
TextSelection wordSelectionAround(String text, int offset) {
  if (text.isEmpty) return const TextSelection.collapsed(offset: 0);
  final i = offset.clamp(0, text.length);
  var start = i;
  var end = i;
  if (i < text.length && _isWordChar(text, i)) {
    start = i;
    end = i + 1;
  } else if (i > 0 && _isWordChar(text, i - 1)) {
    start = i - 1;
    end = i;
  } else {
    return TextSelection.collapsed(offset: i);
  }
  while (start > 0 && _isWordChar(text, start - 1)) {
    start--;
  }
  while (end < text.length && _isWordChar(text, end)) {
    end++;
  }
  return LineRange.withoutEdgeNewlines(
    text,
    TextSelection(baseOffset: start, extentOffset: end),
  );
}

bool _isWordChar(String text, int index) {
  final ch = String.fromCharCode(text.codeUnitAt(index));
  return RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(ch);
}
