import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../ui/app_typography.dart';

/// Glass hover bubble for a description-linked info object.
class InfoDescriptionBubble extends StatelessWidget {
  const InfoDescriptionBubble({
    super.key,
    required this.title,
    this.body = '',
    this.maxHeight = 240,
    this.maxWidth = 320,
  });

  final String title;
  final String body;
  final double maxHeight;
  final double maxWidth;

  static const _radius = 10.0;
  static const _minWidth = 120.0;
  static const _horizontalPadding = 24.0;

  double _bubbleWidth(BuildContext context) {
    final direction = Directionality.of(context);
    final titleStyle = AppTypography.listItemStyle.copyWith(
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.none,
    );
    final bodyStyle = AppTypography.noteBodyStyle.copyWith(
      decoration: TextDecoration.none,
    );
    final innerMax = maxWidth - _horizontalPadding;

    double measure(String text, TextStyle style, {bool wrap = false}) {
      if (text.isEmpty) return 0;
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: direction,
        maxLines: wrap ? null : 1,
      )..layout(maxWidth: innerMax);
      return painter.size.width;
    }

    final contentWidth = math.max(
      measure(title, titleStyle),
      measure(body, bodyStyle, wrap: true),
    );
    if (contentWidth <= 0) return _minWidth;
    return (contentWidth + _horizontalPadding).clamp(_minWidth, maxWidth);
  }

  @override
  Widget build(BuildContext context) {
    if (title.isEmpty && body.isEmpty) return const SizedBox.shrink();

    final width = _bubbleWidth(context);
    final titleStyle = AppTypography.listItemStyle.copyWith(
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.none,
    );
    final bodyStyle = AppTypography.noteBodyStyle.copyWith(
      decoration: TextDecoration.none,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(_radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          width: width,
          constraints: BoxConstraints(maxHeight: maxHeight),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(_radius),
            border: Border.all(color: Colors.white.withValues(alpha: 0.55)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.14),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (title.isNotEmpty)
                  Text(title, style: titleStyle),
                if (title.isNotEmpty && body.isNotEmpty)
                  const SizedBox(height: 6),
                if (body.isNotEmpty)
                  Text(body, style: bodyStyle),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
