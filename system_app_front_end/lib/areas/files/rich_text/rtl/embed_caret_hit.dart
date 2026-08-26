/// Tap placement and run-aware caret — part of the [RTL solution](RTL.md).
///
/// Flutter's `getPositionForPoint` often lands on a BiDi boundary (start of
/// line, or after an English/number run) and paints a downstream caret on the
/// next line. Super Editor does not. Apply in `onTap` the same turn. The
/// visible bar is paint-only ([embedCaretPaintRect]) — do not write selection
/// on keystroke.
library;

import 'package:flutter/rendering.dart';

import './empty_space_caret.dart';

/// Collapsed caret for a tap inside an embed field.
///
/// Padding beside the line → logical line end. Gaps between BiDi runs snap to
/// the nearest glyph. Otherwise Flutter's hit-test, with affinity chosen so
/// the painted caret stays on the line that was tapped.
TextSelection embedCaretForTap({
  required RenderEditable editable,
  required Offset globalPosition,
  required int textLength,
}) {
  if (textLength <= 0) return const TextSelection.collapsed(offset: 0);

  final boxes = [
    for (final b in editable.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: textLength),
    ))
      Rect.fromLTRB(b.left, b.top, b.right, b.bottom),
  ];
  final local = editable.globalToLocal(globalPosition);

  final empty = emptySpaceCaretOffsetFromBoxes(
    boxes: boxes,
    local: local,
    textLength: textLength,
    logicalLineEndAt: (probeOnGlyphs) {
      final probe = editable.getPositionForPoint(
        editable.localToGlobal(probeOnGlyphs),
      );
      final line = editable.getLineAtOffset(probe);
      return line.extentOffset.clamp(0, textLength);
    },
  );
  if (empty != null) {
    return TextSelection.collapsed(
      offset: empty,
      affinity: TextAffinity.upstream,
    );
  }

  var probeGlobal = globalPosition;
  final gap = bidiGapCaretProbe(boxes: boxes, local: local);
  if (gap != null) {
    probeGlobal = editable.localToGlobal(gap);
  }
  return caretSelectionForTap(
    editable: editable,
    globalPosition: probeGlobal,
    textLength: textLength,
  );
}

/// Affinity whose painted caret is closer to the tap — stops end-of-line taps
/// from jumping to the start of the line below.
TextSelection caretSelectionForTap({
  required RenderEditable editable,
  required Offset globalPosition,
  required int textLength,
}) {
  final pos = editable.getPositionForPoint(globalPosition);
  final offset = pos.offset.clamp(0, textLength);
  final local = editable.globalToLocal(globalPosition);

  final down = TextPosition(offset: offset, affinity: TextAffinity.downstream);
  final up = TextPosition(offset: offset, affinity: TextAffinity.upstream);
  late final Rect downRect;
  late final Rect upRect;
  try {
    downRect = editable.getLocalRectForCaret(down);
    upRect = editable.getLocalRectForCaret(up);
  } catch (_) {
    return TextSelection.collapsed(offset: offset, affinity: pos.affinity);
  }

  final downDy = (downRect.center.dy - local.dy).abs();
  final upDy = (upRect.center.dy - local.dy).abs();
  if ((downDy - upDy).abs() > 0.5) {
    return TextSelection.collapsed(
      offset: offset,
      affinity: downDy < upDy ? TextAffinity.downstream : TextAffinity.upstream,
    );
  }
  final downDx = (downRect.left - local.dx).abs();
  final upDx = (upRect.left - local.dx).abs();
  return TextSelection.collapsed(
    offset: offset,
    affinity: downDx <= upDx ? TextAffinity.downstream : TextAffinity.upstream,
  );
}

/// True when the glyph run at [offset] paints RTL (Hebrew), not LTR
/// (English / European numbers inside an RTL paragraph).
bool caretRunIsRtl({
  required RenderEditable? editable,
  required String text,
  required int offset,
  required TextDirection paragraphDir,
}) {
  if (text.isEmpty || editable == null) {
    return paragraphDir == TextDirection.rtl;
  }
  final start = offset > 0 ? offset - 1 : 0;
  final end = (start + 1).clamp(0, text.length);
  if (end <= start) return paragraphDir == TextDirection.rtl;
  try {
    final boxes = editable.getBoxesForSelection(
      TextSelection(baseOffset: start, extentOffset: end),
    );
    if (boxes.isNotEmpty) {
      return boxes.first.direction == TextDirection.rtl;
    }
  } catch (_) {}
  return paragraphDir == TextDirection.rtl;
}

/// Width of the object-field caret bar (Super Editor uses 2px).
const embedCaretBarWidth = 2.0;

/// Visible caret rect for an embed field. Picks upstream vs downstream so the
/// bar stays on the insertion glyph's line (and at that glyph's trailing edge).
///
/// Paint-only: never writes [RenderEditable] selection.
Rect? embedCaretPaintRect({
  required RenderEditable editable,
  required TextSelection selection,
  required int textLength,
}) {
  if (!selection.isValid || !selection.isCollapsed) return null;
  final offset = selection.extentOffset.clamp(0, textLength);
  late final Rect downRect;
  late final Rect upRect;
  try {
    downRect = editable.getLocalRectForCaret(
      TextPosition(offset: offset, affinity: TextAffinity.downstream),
    );
    upRect = editable.getLocalRectForCaret(
      TextPosition(offset: offset, affinity: TextAffinity.upstream),
    );
  } catch (_) {
    return null;
  }

  Rect? glyph;
  var glyphDirection = TextDirection.ltr;
  var caretBeforeGlyph = false;
  if (offset > 0) {
    final boxes = _glyphBoxes(editable, offset - 1, offset);
    if (boxes.isNotEmpty) {
      glyph = boxes.first.toRect();
      glyphDirection = boxes.first.direction;
    }
  } else if (textLength > 0) {
    final boxes = _glyphBoxes(editable, 0, 1);
    if (boxes.isNotEmpty) {
      glyph = boxes.first.toRect();
      glyphDirection = boxes.first.direction;
      caretBeforeGlyph = true;
    }
  }

  final picked = pickCaretPaintRect(
    downstream: downRect,
    upstream: upRect,
    glyph: glyph,
    glyphDirection: glyphDirection,
    caretBeforeGlyph: caretBeforeGlyph,
  );
  return Rect.fromLTWH(
    picked.left,
    picked.top,
    embedCaretBarWidth,
    picked.height,
  );
}

List<TextBox> _glyphBoxes(RenderEditable editable, int start, int end) {
  try {
    return editable.getBoxesForSelection(
      TextSelection(baseOffset: start, extentOffset: end),
    );
  } catch (_) {
    return const [];
  }
}

/// Chooses upstream vs downstream caret geometry from layout boxes.
Rect pickCaretPaintRect({
  required Rect downstream,
  required Rect upstream,
  Rect? glyph,
  required TextDirection glyphDirection,
  required bool caretBeforeGlyph,
}) {
  if (glyph == null) return downstream;
  final downDy = (downstream.center.dy - glyph.center.dy).abs();
  final upDy = (upstream.center.dy - glyph.center.dy).abs();
  if ((downDy - upDy).abs() > 0.5) {
    return downDy < upDy ? downstream : upstream;
  }
  final edgeX = caretBeforeGlyph
      ? (glyphDirection == TextDirection.rtl ? glyph.right : glyph.left)
      : (glyphDirection == TextDirection.rtl ? glyph.left : glyph.right);
  final downDx = (downstream.left - edgeX).abs();
  final upDx = (upstream.left - edgeX).abs();
  return downDx <= upDx ? downstream : upstream;
}
