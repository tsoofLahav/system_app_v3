import 'package:flutter/material.dart';

/// Cross-app color tokens. Use via [AppColors] helpers — not raw Material colors in UI.
abstract final class AppColors {
  // Neutrals (main / home)
  static const canvasNeutralTop = Color(0xFFF7F6F2);
  static const canvasNeutralBottom = Color(0xFFEEECE5);

  // Note surfaces
  static const noteTop = Color(0xFFFCFBF7);
  static const noteBottom = Color(0xFFF4F2EC);
  static const noteBorder = Color(0xFFDCD8CF);
  static const noteShadow = Color(0x0F000000);

  // All app text — one soft charcoal (headers and body share this)
  static const text = Color(0xFF5E5B56);
  static const textHint = Color(0xFF9D988F);

  // Legacy aliases — prefer [text]
  static const noteTitle = text;
  static const noteBody = text;
  static const noteHint = textHint;
  static const noteMeta = textHint;

  // Sidebar
  static const sidebarBg = Color(0xFFF1EFE8);
  static const sidebarBorder = Color(0xFFD8D4CB);

  /// AI menu accent — cyan glow on bottom-bar tools.
  static const aiCyan = Color(0xFF00D4FF);

  /// Pastel topic canvas from accent hex.
  static LinearGradient topicCanvasGradient(
    Color accent, {
    bool isMain = false,
  }) {
    if (isMain) {
      return const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [canvasNeutralTop, canvasNeutralBottom],
      );
    }
    final top = Color.alphaBlend(
      accent.withValues(alpha: 0.045),
      canvasNeutralTop,
    );
    final bottom = Color.alphaBlend(
      accent.withValues(alpha: 0.085),
      canvasNeutralBottom,
    );
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [top, bottom],
    );
  }

  static LinearGradient noteGradient = const LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [noteTop, noteBottom],
  );

  static BoxDecoration noteDecoration({Color? accent}) {
    return BoxDecoration(
      gradient: noteGradient,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: noteBorder.withValues(alpha: 0.82), width: 0.8),
      boxShadow: const [
        BoxShadow(color: noteShadow, blurRadius: 14, offset: Offset(0, 5)),
      ],
    );
  }

  /// Topic-tinted pane surface — same pastel as topic canvas, used inside a card.
  static BoxDecoration topicPaneDecoration(
    Color accent, {
    bool isMain = false,
  }) {
    return BoxDecoration(
      gradient: topicCanvasGradient(accent, isMain: isMain),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: noteBorder.withValues(alpha: 0.72), width: 0.8),
      boxShadow: const [
        BoxShadow(color: noteShadow, blurRadius: 14, offset: Offset(0, 5)),
      ],
    );
  }
}

abstract final class AppSpacing {
  static const xs = 4.0;
  static const sm = 6.0;
  static const md = 12.0;
  static const lg = 18.0;
  static const xl = 26.0;
  static const blockGap = 3.0;
  static const notePadding = EdgeInsets.all(12);
  static const canvasPadding = EdgeInsets.all(12);
}
