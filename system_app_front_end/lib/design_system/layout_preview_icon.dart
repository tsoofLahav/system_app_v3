import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Miniature wireframe of a file layout — fixed-size painter so each option
/// reads clearly in popup menus.
class LayoutPreviewIcon extends StatelessWidget {
  const LayoutPreviewIcon({
    super.key,
    required this.layoutId,
    this.selected = false,
    this.enabled = true,
    this.width = 52,
    this.height = 36,
  });

  final String layoutId;
  final bool selected;
  final bool enabled;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final accent = selected ? primary : AppColors.text;
    final stroke = enabled
        ? accent.withValues(alpha: selected ? 0.95 : 0.72)
        : AppColors.textHint.withValues(alpha: 0.35);
    final fill = enabled
        ? (selected
            ? primary.withValues(alpha: 0.14)
            : AppColors.noteBottom.withValues(alpha: 0.55))
        : AppColors.noteBorder.withValues(alpha: 0.25);

    return Opacity(
      opacity: enabled ? 1 : 0.42,
      child: SizedBox(
        width: width,
        height: height,
        child: CustomPaint(
          painter: _LayoutPreviewPainter(
            layoutId: layoutId,
            stroke: stroke,
            fill: fill,
            frameStroke: selected
                ? primary.withValues(alpha: 0.55)
                : AppColors.noteBorder.withValues(alpha: 0.65),
            selected: selected,
          ),
        ),
      ),
    );
  }
}

class _LayoutPreviewPainter extends CustomPainter {
  _LayoutPreviewPainter({
    required this.layoutId,
    required this.stroke,
    required this.fill,
    required this.frameStroke,
    required this.selected,
  });

  final String layoutId;
  final Color stroke;
  final Color fill;
  final Color frameStroke;
  final bool selected;

  static const _gap = 3.0;
  static const _radius = 2.5;
  static const _inset = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      const Radius.circular(5),
    );
    canvas.drawRRect(
      frame,
      Paint()
        ..color = selected
            ? fill.withValues(alpha: 0.35)
            : AppColors.noteTop,
    );
    canvas.drawRRect(
      frame,
      Paint()
        ..color = frameStroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 1.4 : 1,
    );

    final area = Rect.fromLTWH(
      _inset,
      _inset,
      size.width - _inset * 2,
      size.height - _inset * 2,
    );

    switch (layoutId) {
      case 'single':
        _panel(canvas, area);
      case 'split':
        _split(canvas, area, columns: 2);
      case 'hero_left':
        _hero(canvas, area, largeOnStart: true);
      case 'hero_right':
        _hero(canvas, area, largeOnStart: false);
      case 'row':
        _split(canvas, area, columns: 3);
      case 'grid':
        _grid(canvas, area);
      default:
        _panel(canvas, area);
    }
  }

  void _panel(Canvas canvas, Rect area) => _drawCell(canvas, area);

  void _split(Canvas canvas, Rect area, {required int columns}) {
    final totalGap = _gap * (columns - 1);
    final cellW = (area.width - totalGap) / columns;
    for (var i = 0; i < columns; i++) {
      _drawCell(
        canvas,
        Rect.fromLTWH(
          area.left + i * (cellW + _gap),
          area.top,
          cellW,
          area.height,
        ),
      );
    }
  }

  void _hero(Canvas canvas, Rect area, {required bool largeOnStart}) {
    final largeW = area.width * 0.58;
    final sideW = area.width - largeW - _gap;
    final halfH = (area.height - _gap) / 2;

    final largeRect = largeOnStart
        ? Rect.fromLTWH(area.left, area.top, largeW, area.height)
        : Rect.fromLTWH(area.right - largeW, area.top, largeW, area.height);

    final sideLeft = largeOnStart ? area.left + largeW + _gap : area.left;

    _drawCell(canvas, largeRect);
    _drawCell(
      canvas,
      Rect.fromLTWH(sideLeft, area.top, sideW, halfH),
    );
    _drawCell(
      canvas,
      Rect.fromLTWH(sideLeft, area.top + halfH + _gap, sideW, halfH),
    );
  }

  void _grid(Canvas canvas, Rect area) {
    final cellW = (area.width - _gap) / 2;
    final cellH = (area.height - _gap) / 2;
    for (var row = 0; row < 2; row++) {
      for (var col = 0; col < 2; col++) {
        _drawCell(
          canvas,
          Rect.fromLTWH(
            area.left + col * (cellW + _gap),
            area.top + row * (cellH + _gap),
            cellW,
            cellH,
          ),
        );
      }
    }
  }

  void _drawCell(Canvas canvas, Rect rect) {
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(_radius));

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          fill.withValues(alpha: 1),
          fill.withValues(alpha: 0.65),
        ],
      ).createShader(rect);

    canvas.drawRRect(rrect, fillPaint);
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1,
    );

    // Subtle inner line — suggests note content without clutter.
    final lineY = rect.top + rect.height * 0.38;
    canvas.drawLine(
      Offset(rect.left + rect.width * 0.18, lineY),
      Offset(rect.right - rect.width * 0.18, lineY),
      Paint()
        ..color = stroke.withValues(alpha: 0.28)
        ..strokeWidth = 1
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _LayoutPreviewPainter old) =>
      old.layoutId != layoutId ||
      old.stroke != stroke ||
      old.fill != fill ||
      old.frameStroke != frameStroke ||
      old.selected != selected;
}
