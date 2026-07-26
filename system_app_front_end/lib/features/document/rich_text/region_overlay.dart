import 'package:flutter/material.dart';

import '../../../design_system/app_typography.dart';
import '../inline_document_model.dart';

/// Host for inline region hints (per-segment labels only).
class RegionOverlayHost extends StatelessWidget {
  const RegionOverlayHost({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
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
