import 'package:flutter/material.dart';

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
      final start = selection.start.clamp(0, text.length);
      final end = selection.end.clamp(0, text.length);
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
}
