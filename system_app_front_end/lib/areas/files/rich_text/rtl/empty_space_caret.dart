/// Empty-padding caret correction — part of the [RTL solution](RTL.md).
///
/// Taps **on glyphs** stay with Flutter. Taps in empty padding beside/below
/// painted text use the logical line end ([RenderEditable.getLineAtOffset]).
/// Apply in `onTap` before paint — never post-frame.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

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
@visibleForTesting
int? emptySpaceCaretOffsetFromBoxes({
  required List<Rect> boxes,
  required Offset local,
  required int textLength,
  int Function(Offset probeOnGlyphs)? logicalLineEndAt,
}) {
  if (textLength <= 0) return 0;
  if (boxes.isEmpty) return textLength;

  var lastBottom = boxes.first.bottom;
  for (final box in boxes) {
    if (box.bottom > lastBottom) lastBottom = box.bottom;
  }

  if (local.dy > lastBottom + 0.5) return textLength;

  final onLine = [
    for (final box in boxes)
      if (local.dy >= box.top - 0.5 && local.dy <= box.bottom + 0.5) box,
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
