import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../ui/app_colors.dart';

/// Chart chrome for a table object with chart quality enabled.
class TableChartView extends StatelessWidget {
  const TableChartView({
    super.key,
    required this.type,
    required this.values,
    required this.labels,
    required this.colors,
    required this.textDirection,
    this.onSecondaryTapDown,
    this.height = 88,
  });

  final String type;
  final List<double> values;
  final List<String> labels;
  final List<Color> colors;
  final TextDirection textDirection;
  final GestureTapDownCallback? onSecondaryTapDown;
  final double height;

  Color _colorAt(int i) {
    if (colors.isEmpty) return AppColors.primary;
    return colors[i % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final chart = values.isEmpty
        ? const SizedBox.expand()
        : CustomPaint(
            painter: switch (type) {
              'line' => _LineChartPainter(
                values: values,
                colors: [for (var i = 0; i < values.length; i++) _colorAt(i)],
                textDirection: textDirection,
              ),
              'pie' => _PieChartPainter(
                values: values,
                colors: [for (var i = 0; i < values.length; i++) _colorAt(i)],
                textDirection: textDirection,
              ),
              _ => _BarChartPainter(
                values: values,
                colors: [for (var i = 0; i < values.length; i++) _colorAt(i)],
                textDirection: textDirection,
              ),
            },
            child: const SizedBox.expand(),
          );

    return GestureDetector(
      onSecondaryTapDown: onSecondaryTapDown,
      child: SizedBox(height: height, child: chart),
    );
  }
}

int _visualSlot(int i, int count, TextDirection direction) {
  if (count <= 0) return 0;
  return direction == TextDirection.rtl ? count - 1 - i : i;
}

class _BarChartPainter extends CustomPainter {
  _BarChartPainter({
    required this.values,
    required this.colors,
    required this.textDirection,
  });

  final List<double> values;
  final List<Color> colors;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    final maxVal = values
        .fold<double>(0, (a, b) => a > b ? a : b)
        .clamp(1.0, double.infinity);
    final gap = size.width / values.length;
    final barWidth = gap * 0.55;
    for (var i = 0; i < values.length; i++) {
      final slot = _visualSlot(i, values.length, textDirection);
      final h = (values[i] / maxVal).clamp(0.04, 1.0) * size.height;
      final left = gap * slot + (gap - barWidth) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, size.height - h, barWidth, h),
          const Radius.circular(2),
        ),
        Paint()..color = colors[i].withValues(alpha: 0.72),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter old) =>
      old.values != values ||
      old.colors != colors ||
      old.textDirection != textDirection;
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter({
    required this.values,
    required this.colors,
    required this.textDirection,
  });

  final List<double> values;
  final List<Color> colors;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxVal = values
        .fold<double>(0, (a, b) => a > b ? a : b)
        .clamp(1.0, double.infinity);
    final dx = values.length == 1
        ? size.width / 2
        : size.width / (values.length - 1);
    Offset point(int i) {
      final slot = _visualSlot(i, values.length, textDirection);
      final x = values.length == 1 ? size.width / 2 : dx * slot;
      final y =
          size.height -
          (values[i] / maxVal).clamp(0.0, 1.0) * (size.height - 4) -
          2;
      return Offset(x, y);
    }

    final order = [
      for (var slot = 0; slot < values.length; slot++)
        textDirection == TextDirection.rtl ? values.length - 1 - slot : slot,
    ];
    for (var s = 0; s < order.length - 1; s++) {
      final a = order[s];
      final b = order[s + 1];
      canvas.drawLine(
        point(a),
        point(b),
        Paint()
          ..color = colors[a]
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    }
    for (var i = 0; i < values.length; i++) {
      canvas.drawCircle(point(i), 3, Paint()..color = colors[i]);
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter old) =>
      old.values != values ||
      old.colors != colors ||
      old.textDirection != textDirection;
}

class _PieChartPainter extends CustomPainter {
  _PieChartPainter({
    required this.values,
    required this.colors,
    required this.textDirection,
  });

  final List<double> values;
  final List<Color> colors;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (a, b) => a + (b < 0 ? 0 : b));
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: math.min(size.width, size.height) - 8,
      height: math.min(size.width, size.height) - 8,
    );
    if (total <= 0) {
      canvas.drawOval(
        rect,
        Paint()..color = colors.first.withValues(alpha: 0.2),
      );
      return;
    }
    final indices = [
      for (var i = 0; i < values.length; i++)
        textDirection == TextDirection.rtl ? values.length - 1 - i : i,
    ];
    var start = -math.pi / 2;
    for (final i in indices) {
      final sweep = (values[i].clamp(0, double.infinity) / total) * math.pi * 2;
      canvas.drawArc(
        rect,
        start,
        sweep,
        true,
        Paint()..color = colors[i].withValues(alpha: 0.85),
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _PieChartPainter old) =>
      old.values != values ||
      old.colors != colors ||
      old.textDirection != textDirection;
}
