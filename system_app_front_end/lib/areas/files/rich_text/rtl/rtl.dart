/// Fluent RTL / BiDi for the file editor.
///
/// **Source of truth for behavior:** [RTL.md](RTL.md) in this folder.
///
/// Pieces:
/// - [detectParagraphTextDirection] / [resolveFieldTextDirection] — base direction
/// - [rtlCaretMotionActions] / [wrapVisualCaretMotion] — visual arrow keys
/// - [emptySpaceCaretOffset] — taps in empty padding beside/below glyphs
///
/// Wire these only through [FormattedTextField]. Do not reinvent caret math
/// elsewhere in the document flow.
library;

import 'package:flutter/widgets.dart';

import './paragraph_text_direction.dart';
import './rtl_caret_motion.dart';

export './empty_space_caret.dart';
export './paragraph_text_direction.dart';
export './rtl_caret_motion.dart';

/// Paragraph [textDirection]: first strong character, else [ambient] UI locale.
TextDirection resolveFieldTextDirection(String text, TextDirection ambient) {
  return detectParagraphTextDirection(text) ?? ambient;
}

/// Collapsed caret at a logical end (line / part). Upstream affinity keeps
/// soft-wrap and BiDi boundaries on the end-of-line side.
TextSelection collapsedAtLogicalEnd(int offset) {
  return TextSelection.collapsed(
    offset: offset,
    affinity: TextAffinity.upstream,
  );
}

/// Applies [rtlCaretMotionActions] when [textDirection] is RTL; LTR is a no-op.
Widget wrapVisualCaretMotion({
  required TextDirection textDirection,
  required Map<Type, Action<Intent>> actions,
  required Widget child,
}) {
  if (textDirection != TextDirection.rtl) return child;
  return Actions(actions: actions, child: child);
}
