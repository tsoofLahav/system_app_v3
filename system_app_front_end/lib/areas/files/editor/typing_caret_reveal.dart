import 'package:flutter/widgets.dart';

/// Reveal only overflow below the viewport, never recenter or scroll upward.
/// Call after layout for a local text edit, not for selection changes or refresh.
void revealTypingCaretBelow({
  required BuildContext viewportContext,
  required ScrollPosition position,
  required Rect globalCaret,
}) {
  final viewport = viewportContext.findRenderObject();
  if (viewport is! RenderBox ||
      !viewport.hasSize ||
      !position.hasContentDimensions)
    return;
  final bottom = viewport.localToGlobal(Offset(0, viewport.size.height)).dy;
  final overflow = globalCaret.bottom - bottom;
  if (overflow <= 0) return;
  final target = (position.pixels + overflow).clamp(
    position.minScrollExtent,
    position.maxScrollExtent,
  );
  if (target > position.pixels) position.jumpTo(target);
}
