import 'package:flutter/material.dart';

/// Character range a format action applies to.
///
/// Resolved once when the block context menu opens. Never re-derived after
/// focus/selection changes during the menu.
class FormatRange {
  const FormatRange({required this.start, required this.end});

  final int start;
  final int end;

  bool get isValid => end > start;

  @override
  bool operator ==(Object other) =>
      other is FormatRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  TextSelection get selection =>
      TextSelection(baseOffset: start, extentOffset: end);

  /// Highlighted text, or the paragraph at the caret when nothing is marked.
  static FormatRange resolve(String text, TextSelection selection) {
    if (!selection.isValid) {
      return const FormatRange(start: 0, end: 0);
    }

    if (!selection.isCollapsed) {
      final start = selection.start.clamp(0, text.length);
      final end = selection.end.clamp(0, text.length);
      if (end > start) {
        return FormatRange(start: start, end: end);
      }
    }

    final caret = selection.baseOffset.clamp(0, text.length);
    final paragraphStart =
        caret == 0 ? 0 : text.lastIndexOf('\n', caret - 1) + 1;
    final nextNewline = text.indexOf('\n', caret);
    final paragraphEnd = nextNewline == -1 ? text.length : nextNewline;

    if (paragraphEnd <= paragraphStart) {
      return FormatRange(start: caret, end: caret);
    }
    return FormatRange(start: paragraphStart, end: paragraphEnd);
  }

  /// Captured on secondary pointer-down before the menu opens.
  static FormatRange? pending;

  /// Only the first capture counts until [consume] or [clearPending] — later
  /// calls (e.g. from the block menu after focus loss) must not replace a
  /// valid selection with a collapsed caret / whole paragraph.
  static void capturePending(String text, TextSelection selection) {
    if (pending != null && pending!.isValid) return;
    pending = resolve(text, selection);
  }

  static FormatRange consume(String text, TextSelection currentSelection) {
    final early = pending;
    pending = null;
    if (early != null) return early;
    return resolve(text, currentSelection);
  }

  static void clearPending() => pending = null;
}
