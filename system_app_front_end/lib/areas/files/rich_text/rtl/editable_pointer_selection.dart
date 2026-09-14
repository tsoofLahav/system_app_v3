import 'package:flutter/rendering.dart';
import 'package:characters/characters.dart';

/// Hit-test the same rendered grapheme boxes that paint selection. A BiDi run
/// boundary must not redirect a pointer to the far side of a number run.
TextSelection editablePointerSelection({
  required RenderEditable editable,
  required String text,
  required Offset global,
  bool wordBoundariesOnly = false,
}) {
  final nativePosition = editable.getPositionForPoint(global);
  final nativeLine = editable.getLineAtOffset(nativePosition);
  if (text.substring(nativeLine.start.clamp(0, text.length), nativeLine.end.clamp(0, text.length)).trim().isEmpty) {
    return TextSelection.collapsed(offset: nativePosition.offset.clamp(0, text.length), affinity: nativePosition.affinity);
  }
  final point = editable.globalToLocal(global);
  var bestScore = double.infinity;
  var bestOffset = 0;
  var bestAffinity = TextAffinity.downstream;
  var start = 0;
  final word = RegExp(r'[\p{L}\p{N}\p{M}]', unicode: true);
  bool boundary(int offset) =>
      offset == 0 ||
      offset == text.length ||
      !word.hasMatch(text.substring(offset - 1, offset)) ||
      !word.hasMatch(text.substring(offset, offset + 1));
  for (final cluster in text.characters) {
    final end = start + cluster.length;
    if (cluster != '\n' && cluster != '\r\n') {
      final boxes = editable.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: end),
      );
      for (final box in boxes) {
        if (box.right <= box.left) continue;
        for (final edge in [(start, box.start), (end, box.end)]) {
          if (wordBoundariesOnly && !boundary(edge.$1)) continue;
          final dy = point.dy < box.top
              ? box.top - point.dy
              : point.dy > box.bottom
              ? point.dy - box.bottom
              : 0.0;
          final score = dy * 10000 + (edge.$2 - point.dx).abs();
          if (score >= bestScore) continue;
          bestScore = score;
          bestOffset = edge.$1;
          final target = Offset(edge.$2, (box.top + box.bottom) / 2);
          final up = editable.getLocalRectForCaret(
            TextPosition(offset: bestOffset, affinity: TextAffinity.upstream),
          );
          final down = editable.getLocalRectForCaret(
            TextPosition(offset: bestOffset, affinity: TextAffinity.downstream),
          );
          bestAffinity =
              (up.centerLeft - target).distanceSquared <
                  (down.centerLeft - target).distanceSquared
              ? TextAffinity.upstream
              : TextAffinity.downstream;
        }
      }
    }
    start = end;
  }
  if (!bestScore.isFinite) {
    final native = editable.getPositionForPoint(global);
    return TextSelection.collapsed(
      offset: native.offset.clamp(0, text.length),
      affinity: native.affinity,
    );
  }
  return TextSelection.collapsed(offset: bestOffset, affinity: bestAffinity);
}
