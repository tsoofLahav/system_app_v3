import 'package:flutter/material.dart';

import '../../../design_system/app_colors.dart';
import '../../../design_system/app_typography.dart';
import '../inline_document_model.dart';

/// Applies subtle list/table styling hints for inline text regions.
class RegionOverlayHost extends StatelessWidget {
  const RegionOverlayHost({
    super.key,
    required this.document,
    required this.child,
  });

  final InlineDocument document;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (document.regions.isEmpty) return child;
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _RegionHintPainter(document: document),
            ),
          ),
        ),
      ],
    );
  }
}

class _RegionHintPainter extends CustomPainter {
  _RegionHintPainter({required this.document});

  final InlineDocument document;

  @override
  void paint(Canvas canvas, Size size) {
    final listPaint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.06)
      ..style = PaintingStyle.fill;
    final tablePaint = Paint()
      ..color = AppColors.noteBorder.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.75;

    for (final region in document.regions) {
      if (region.kind == 'list') {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(0, 0, size.width, size.height),
            const Radius.circular(4),
          ),
          listPaint,
        );
      } else if (region.kind == 'table') {
        canvas.drawRect(Rect.fromLTWH(8, 0, size.width - 16, size.height), tablePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RegionHintPainter oldDelegate) =>
      oldDelegate.document != document;
}

/// Inline label shown near list/table regions in the document margin.
class RegionStyleHint extends StatelessWidget {
  const RegionStyleHint({
    super.key,
    required this.region,
    required this.text,
  });

  final DocumentRegion region;
  final String text;

  @override
  Widget build(BuildContext context) {
    if (!text.contains('\n') && region.end - region.start < 2) {
      return const SizedBox.shrink();
    }
    final label = region.kind == 'table'
        ? 'Table'
        : region.listStyle == 'numbered'
            ? 'Numbered list'
            : 'Bullet list';
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(label, style: AppTypography.metaStyle),
    );
  }
}
