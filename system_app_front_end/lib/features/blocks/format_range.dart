import 'package:flutter/material.dart';

import '../../core/text/line_range.dart';

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

  /// Highlighted text, or the line at the caret when nothing is marked.
  static FormatRange resolve(String text, TextSelection selection) {
    final range = LineRange.resolve(text, selection);
    return FormatRange(start: range.start, end: range.end);
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
