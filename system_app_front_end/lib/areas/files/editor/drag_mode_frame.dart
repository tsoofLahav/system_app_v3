import 'package:flutter/material.dart';

import '../../ui/glass_surface.dart';

/// Gentle glass frame used by object Move Mode and task Reorder Mode.
///
/// No labels — the frame alone signals that the content is pickable.
class DragModeFrame extends StatelessWidget {
  const DragModeFrame({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    this.borderRadius,
  });

  /// Tight rounded-square chip that hugs its child (task Reorder Mode).
  const DragModeFrame.chip({
    super.key,
    required this.child,
  })  : padding = const EdgeInsets.all(10),
        borderRadius = const BorderRadius.all(Radius.circular(10));

  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius? borderRadius;

  static BorderRadius get defaultRadius =>
      BorderRadius.circular(AppGlassStyle.floatingRadius * 0.7);

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? defaultRadius;
    return GlassSurface.styled(
      style: AppGlassStyle.dragMode,
      borderRadius: radius,
      border: AppGlassStyle.dragModeBorder,
      padding: padding,
      child: child,
    );
  }
}
