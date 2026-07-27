import 'package:flutter/material.dart';

/// Paint-only selection highlight rects (from [RenderEditable] when possible).
class FrozenSelectionPainter extends CustomPainter {
  FrozenSelectionPainter({
    required this.rects,
    required this.selectionColor,
  });

  final List<Rect> rects;
  final Color selectionColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (rects.isEmpty) return;
    final paint = Paint()..color = selectionColor;
    for (final rect in rects) {
      canvas.drawRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant FrozenSelectionPainter oldDelegate) {
    return selectionColor != oldDelegate.selectionColor ||
        !rectsEqual(rects, oldDelegate.rects);
  }

  static bool rectsEqual(List<Rect> a, List<Rect> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
