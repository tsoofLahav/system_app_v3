import 'package:flutter/material.dart';

import '../../design_system/app_icons.dart';

/// Collapse/expand chevron at the leading edge of a row; mirrors in RTL.
class DisclosureIcon extends StatelessWidget {
  const DisclosureIcon({
    super.key,
    required this.expanded,
    this.size = 18,
    this.color,
  });

  final bool expanded;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final icon = AppIcon(
      expanded ? AppIcons.chevronDown : AppIcons.chevronRight,
      size: size,
      color: color,
    );
    if (expanded) return icon;

    final isRtl = Directionality.of(context) == TextDirection.rtl;
    if (!isRtl) return icon;

    return Transform.flip(flipX: true, child: icon);
  }
}
