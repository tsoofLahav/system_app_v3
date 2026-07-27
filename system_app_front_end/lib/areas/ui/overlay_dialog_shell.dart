import 'package:flutter/material.dart';

/// Full-screen transparent shell for overlay dialogs.
///
/// Taps on the scrim dismiss the route; taps on [child] are absorbed.
class OverlayDialogShell extends StatelessWidget {
  const OverlayDialogShell({
    super.key,
    required this.child,
    this.onDismiss,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
  });

  final Widget child;
  final VoidCallback? onDismiss;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        onTap: onDismiss,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: padding,
          child: Center(
            child: GestureDetector(
              onTap: () {},
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
