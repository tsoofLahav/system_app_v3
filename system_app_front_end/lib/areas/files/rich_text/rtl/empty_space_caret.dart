/// Empty-padding caret correction — part of the [RTL solution](RTL.md).
///
/// Taps **on glyphs** (few px slop) stay with Flutter. Empty `boxes` stay with
/// Flutter. Taps in empty padding **beside the line slot** use the logical line
/// end ([RenderEditable.getLineAtOffset]). Extra cell/row padding above or
/// below ink is not a line-end jump. Apply in `onTap` before paint — never
/// post-frame.
library;

import 'package:flutter/rendering.dart';

/// Hit slop around glyph ink so a tap on a letter in a tall cell stays Flutter.
const double _kEmptySpaceGlyphSlop = 4;

/// Caret offset for a tap in empty padding, or null when the tap is on glyphs.
int? emptySpaceCaretOffset({
  required RenderEditable editable,
  required Offset globalPosition,
  required int textLength,
}) {
  if (textLength <= 0) return 0;

  final boxes = editable.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: textLength),
  );
  return emptySpaceCaretOffsetFromBoxes(
    boxes: [
      for (final b in boxes) Rect.fromLTRB(b.left, b.top, b.right, b.bottom),
    ],
    local: editable.globalToLocal(globalPosition),
    textLength: textLength,
    logicalLineEndAt: (probeOnGlyphs) {
      final probe = editable.getPositionForPoint(
        editable.localToGlobal(probeOnGlyphs),
      );
      final line = editable.getLineAtOffset(probe);
      return line.extentOffset.clamp(0, textLength);
    },
  );
}

/// Pure geometry for [emptySpaceCaretOffset] — testable without a field.
int? emptySpaceCaretOffsetFromBoxes({
  required List<Rect> boxes,
  required Offset local,
  required int textLength,
  int Function(Offset probeOnGlyphs)? logicalLineEndAt,
}) {
  if (textLength <= 0) return 0;
  if (boxes.isEmpty) return null;

  for (final box in boxes) {
    if (box.inflate(_kEmptySpaceGlyphSlop).contains(local)) return null;
  }

  final onLine = [
    for (final box in boxes)
      if (local.dy >= box.top - _kEmptySpaceGlyphSlop &&
          local.dy <= box.bottom + _kEmptySpaceGlyphSlop)
        box,
  ];
  if (onLine.isEmpty) return null;

  var left = onLine.first.left;
  var right = onLine.first.right;
  for (final box in onLine) {
    if (box.left < left) left = box.left;
    if (box.right > right) right = box.right;
  }

  if (local.dx < left - 0.5 || local.dx > right + 0.5) {
    final midX = (left + right) / 2;
    final midY = (onLine.first.top + onLine.first.bottom) / 2;
    final resolve = logicalLineEndAt;
    if (resolve != null) return resolve(Offset(midX, midY));
    return textLength;
  }

  return null;
}

/// Probe slightly inside the nearest glyph when the tap sits in a BiDi gap
/// on the line (between Hebrew and a number/English run). Null on a glyph
/// or in padding beside the line — those use other rules.
Offset? bidiGapCaretProbe({required List<Rect> boxes, required Offset local}) {
  if (boxes.isEmpty) return null;

  for (final box in boxes) {
    if (box.inflate(_kEmptySpaceGlyphSlop).contains(local)) return null;
  }

  final onLine = [
    for (final box in boxes)
      if (local.dy >= box.top - _kEmptySpaceGlyphSlop &&
          local.dy <= box.bottom + _kEmptySpaceGlyphSlop)
        box,
  ];
  if (onLine.isEmpty) return null;

  var left = onLine.first.left;
  var right = onLine.first.right;
  for (final box in onLine) {
    if (box.left < left) left = box.left;
    if (box.right > right) right = box.right;
  }
  if (local.dx < left - 0.5 || local.dx > right + 0.5) return null;

  Rect nearest = onLine.first;
  var best = _horizontalGap(local.dx, nearest);
  for (final box in onLine) {
    final d = _horizontalGap(local.dx, box);
    if (d < best) {
      best = d;
      nearest = box;
    }
  }
  final midY = (nearest.top + nearest.bottom) / 2;
  final x = local.dx < nearest.left ? nearest.left + 0.5 : nearest.right - 0.5;
  return Offset(x, midY);
}

double _horizontalGap(double dx, Rect box) {
  if (dx < box.left) return box.left - dx;
  if (dx > box.right) return dx - box.right;
  return 0;
}
