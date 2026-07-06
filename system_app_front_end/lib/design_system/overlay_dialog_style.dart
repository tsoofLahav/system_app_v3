import 'package:flutter/material.dart';

/// Shared scrim + file-card styling for transparent overlay dialogs.
abstract final class OverlayDialogStyle {
  /// Dark but not heavy — keeps frosted cards from looking muddy grey.
  static Color get barrierColor => Colors.black.withValues(alpha: 0.18);

  static const fileCardTintOpacity = 0.32;
  static const fileCardBorderRadius = 14.0;

  /// Bright lift glow for frosted cards on the dark overlay scrim.
  static List<BoxShadow> get fileCardShadow => [
        BoxShadow(
          color: Colors.white.withValues(alpha: 0.14),
          blurRadius: 20,
          offset: const Offset(0, 5),
        ),
        BoxShadow(
          color: Colors.white.withValues(alpha: 0.07),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ];
}
