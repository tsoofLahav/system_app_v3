import 'package:flutter/material.dart';

import './app_colors.dart';
import './glass_surface.dart';

/// Miniature of an object look — samples in the design dialog.
class ObjectLookPreview extends StatelessWidget {
  const ObjectLookPreview({
    super.key,
    required this.lookId,
    required this.kind,
    this.selected = false,
    this.width = 52,
    this.height = 36,
  });

  final String lookId;
  final String kind;
  final bool selected;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final ring = selected
        ? AppColors.primaryBright.withValues(alpha: 0.72)
        : AppColors.noteBorder.withValues(alpha: 0.55);
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: ring, width: selected ? 1.2 : 0.7),
        ),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: lookId == 'glass'
              ? GlassSurface.styled(
                  style: AppGlassStyle.dragMode,
                  borderRadius: BorderRadius.circular(3),
                  border: AppGlassStyle.dragModeBorder,
                  child: _LookMini(kind: kind, lookId: lookId),
                )
              : _LookMini(kind: kind, lookId: lookId),
        ),
      ),
    );
  }
}

class _LookMini extends StatelessWidget {
  const _LookMini({required this.kind, required this.lookId});

  final String kind;
  final String lookId;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _LookMiniPainter(kind: kind, lookId: lookId),
    );
  }
}

class _LookMiniPainter extends CustomPainter {
  _LookMiniPainter({required this.kind, required this.lookId});

  final String kind;
  final String lookId;

  @override
  void paint(Canvas canvas, Size size) {
    final area = Offset.zero & size;
    final line = Paint()
      ..color = AppColors.noteBorder.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9;
    final wash = Paint()
      ..color = AppColors.noteTop.withValues(alpha: 0.72)
      ..style = PaintingStyle.fill;
    final paper = Paint()
      ..color = AppColors.noteBottom.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;

    RRect box() => RRect.fromRectAndRadius(area, const Radius.circular(2));

    void textLines({required bool indent}) {
      final ink = Paint()
        ..color = AppColors.text.withValues(alpha: 0.45)
        ..strokeWidth = 1.1
        ..strokeCap = StrokeCap.round;
      final left = indent ? 5.0 : 3.0;
      for (var i = 0; i < 3; i++) {
        final y = 5.0 + i * 6.0;
        if (y > size.height - 3) break;
        canvas.drawLine(Offset(left, y), Offset(size.width - 3, y), ink);
      }
    }

    void grid({required bool vertical, required bool outer, Color? fill}) {
      if (fill != null) {
        canvas.drawRRect(box(), Paint()..color = fill);
      } else {
        canvas.drawRRect(box(), paper);
      }
      final midX = size.width / 2;
      final midY = size.height / 2;
      if (outer) canvas.drawRRect(box(), line);
      canvas.drawLine(Offset(3, midY), Offset(size.width - 3, midY), line);
      if (vertical) {
        canvas.drawLine(Offset(midX, 3), Offset(midX, size.height - 3), line);
      }
    }

    void photo({required bool framed, required bool filled}) {
      final inner = area.deflate(framed || filled ? 2 : 0);
      if (filled) {
        canvas.drawRRect(box(), wash);
      }
      final pic = RRect.fromRectAndRadius(inner, const Radius.circular(1.5));
      canvas.drawRRect(
        pic,
        Paint()..color = AppColors.text.withValues(alpha: 0.22),
      );
      if (framed) canvas.drawRRect(box(), line);
    }

    switch (kind) {
      case 'table':
        switch (lookId) {
          case 'outline':
            grid(vertical: true, outer: true);
          case 'fill':
            grid(
              vertical: true,
              outer: false,
              fill: AppColors.noteTop.withValues(alpha: 0.72),
            );
          case 'lined':
            grid(vertical: false, outer: false);
          case 'plain':
          case 'open':
            grid(vertical: true, outer: false);
          case 'glass':
            grid(vertical: true, outer: false);
          default:
            grid(
              vertical: true,
              outer: true,
              fill: lookId == 'glass'
                  ? null
                  : AppColors.noteTop.withValues(alpha: 0.28),
            );
        }
      case 'image':
        switch (lookId) {
          case 'outline':
          case 'card':
          case 'frame':
            photo(framed: true, filled: false);
          case 'fill':
            photo(framed: false, filled: true);
          default:
            photo(framed: false, filled: false);
        }
      default:
        switch (lookId) {
          case 'plain':
            canvas.drawRRect(box(), paper);
            textLines(indent: false);
          case 'glass':
            canvas.drawRRect(box(), paper);
            textLines(indent: false);
          case 'outline':
            canvas.drawRRect(box(), line);
            textLines(indent: false);
          case 'fill':
            canvas.drawRRect(box(), wash);
            textLines(indent: false);
          case 'ruled':
            canvas.drawRRect(box(), paper);
            canvas.drawLine(
              const Offset(3, 2),
              Offset(3, size.height - 2),
              Paint()
                ..color = AppColors.noteBorder.withValues(alpha: 0.9)
                ..strokeWidth = 1.6
                ..strokeCap = StrokeCap.round,
            );
            textLines(indent: true);
          default:
            canvas.drawRRect(box(), wash);
            canvas.drawRRect(box(), line);
            textLines(indent: false);
        }
    }
  }

  @override
  bool shouldRepaint(covariant _LookMiniPainter old) =>
      old.kind != kind || old.lookId != lookId;
}

/// Colour-set sample: a row of palette dots.
class PalettePreview extends StatelessWidget {
  const PalettePreview({super.key, required this.hexes, this.selected = false});

  final List<String> hexes;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final ring = selected
        ? AppColors.primaryBright.withValues(alpha: 0.8)
        : AppColors.noteBorder.withValues(alpha: 0.55);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: ring, width: selected ? 1.2 : 0.7),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: Row(
          children: [
            for (var i = 0; i < hexes.length && i < 8; i++) ...[
              if (i > 0) const SizedBox(width: 3),
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: AppColors.colorFromHex(hexes[i]),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.text.withValues(alpha: 0.12),
                    width: 0.5,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
