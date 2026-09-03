/// Fluent RTL / BiDi for the file editor.
///
/// **Source of truth for behavior:** [RTL.md](RTL.md) in this folder.
///
/// Pieces:
/// - [detectParagraphTextDirection] / [resolveFieldTextDirection] — base direction
/// - [rtlCaretMotionActions] / [wrapVisualCaretMotion] — visual arrow keys (embeds; flip RTL runs only)
/// - [emptySpaceCaretOffset] / [embedCaretForTap] / [bidiAwareOffsetFromBoxes] — padding, BiDi gaps, marking
/// - [ambientAwareTextBuilders] / [SuperEditorVisualCaretPlugin] / [SuperEditorBidiCaretTapHandler] — Super Editor
/// - [visualIosExpandedHandleLayout] — iOS handles: upstream/downstream identity, tight wash snap
///
/// Wire caret/direction helpers through [FormattedTextField] (embeds) and
/// Super Editor builders/plugins — see [RTL.md]. Do not reinvent caret math in
/// `DocumentTextFlow`.
library;

import 'package:flutter/widgets.dart';

import './paragraph_text_direction.dart';
import './rtl_caret_motion.dart';

export './empty_space_caret.dart';
export './embed_caret_hit.dart';
export './ios_visual_handles.dart';
export './paragraph_text_direction.dart';
export './rtl_caret_motion.dart';
export './super_editor_bidi_caret.dart';
export './super_editor_text_direction.dart';
export './super_editor_visual_caret.dart';

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

/// Always wraps [child] in [Actions] so LTR↔RTL does not remount the field.
///
/// [actions] decide whether to flip (RTL glyph run vs English/number run).
Widget wrapVisualCaretMotion({
  required TextDirection textDirection,
  required Map<Type, Action<Intent>> actions,
  required Widget child,
}) {
  assert(
    textDirection == TextDirection.ltr || textDirection == TextDirection.rtl,
  );
  return Actions(actions: actions, child: child);
}
