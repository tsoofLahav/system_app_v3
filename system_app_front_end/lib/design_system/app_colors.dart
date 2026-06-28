import 'package:flutter/material.dart';

/// Cross-app color tokens. Use via [AppColors] helpers — not raw Material colors in UI.
abstract final class AppColors {
  // Neutrals (main / home) — almost white, slightly cooler than note surfaces
  static const canvasNeutralTop = Color(0xFFFFFEFE);
  static const canvasNeutralBottom = Color(0xFFFAFAF8);

  // Note surfaces
  static const noteTop = Color(0xFFFCFBF7);
  static const noteBottom = Color(0xFFF4F2EC);
  static const mainNoteTop = Color(0xFFFFFFFF);
  static const mainNoteBottom = Color(0xFFFFFFFF);
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

  /// Environmental background — always neutral (topic color lives on file panes).
  static const neutralCanvasGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [canvasNeutralTop, canvasNeutralBottom],
  );

  /// Desaturated topic accent for pane fills (borders use [topicPaneBorder]).
  static Color uiAccent(Color accent) =>
      Color.lerp(accent, Colors.white, 0.18) ?? accent;

  /// Vivid topic accent for pane outlines.
  static Color topicPaneBorder(Color topicAccent, String fileType) {
    final vivid = Color.lerp(topicAccent, Colors.white, 0.08) ?? topicAccent;
    final strength = fileTypeTintStrength(fileType);
    final alpha = 0.36 + strength * 0.42;
    return vivid.withValues(alpha: alpha.clamp(0.0, 1.0));
  }

  /// Tint strength by file type — semantic, stable when files reorder.
  static double fileTypeTintStrength(String fileType) {
    switch (fileType) {
      case 'plan':
        return 0.17;
      case 'tasks':
        return 0.13;
      case 'doc':
        return 0.10;
      case 'overview':
        return 0.075;
      case 'board':
        return 0.09;
      case 'text':
        return 0.045;
      default:
        return 0.08;
    }
  }

  static const filePaneBorderWidth = 0.5;

  static LinearGradient filePaneGradient(Color topicAccent, String fileType) {
    final accent = uiAccent(topicAccent);
    final strength = fileTypeTintStrength(fileType);
    final top = Color.alphaBlend(
      accent.withValues(alpha: strength * 0.72),
      mainNoteTop,
    );
    final bottom = Color.alphaBlend(
      accent.withValues(alpha: strength * 0.88),
      mainNoteBottom,
    );
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [top, bottom],
    );
  }

  /// Pastel topic canvas from accent hex.
  @Deprecated('Canvas is always neutral; use neutralCanvasGradient')
  static LinearGradient topicCanvasGradient(
    Color accent, {
    bool isMain = false,
  }) {
    return neutralCanvasGradient;
  }

  static LinearGradient noteGradient = const LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [noteTop, noteBottom],
  );

  static BoxDecoration noteDecoration() {
    return BoxDecoration(
      gradient: noteGradient,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: noteBorder.withValues(alpha: 0.82), width: 0.8),
      boxShadow: const [
        BoxShadow(color: noteShadow, blurRadius: 14, offset: Offset(0, 5)),
      ],
    );
  }

  static BoxDecoration mainNoteDecoration() {
    return BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [mainNoteTop, mainNoteBottom],
      ),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: noteBorder.withValues(alpha: 0.55), width: 0.8),
      boxShadow: const [
        BoxShadow(color: noteShadow, blurRadius: 14, offset: Offset(0, 5)),
      ],
    );
  }

  /// File pane tinted by topic color + file type (main topic stays white).
  static BoxDecoration filePaneDecoration(
    Color topicAccent,
    String fileType, {
    bool isMainTopic = false,
  }) {
    if (isMainTopic) return mainNoteDecoration();
    return BoxDecoration(
      gradient: filePaneGradient(topicAccent, fileType),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(
        color: topicPaneBorder(topicAccent, fileType),
        width: filePaneBorderWidth,
      ),
      boxShadow: const [
        BoxShadow(color: noteShadow, blurRadius: 14, offset: Offset(0, 5)),
      ],
    );
  }

  /// Lighter wash of the file pane surface (summary sits inside the pane).
  static BoxDecoration summaryPaneDecoration(
    Color topicAccent,
    String fileType, {
    bool isMainTopic = false,
  }) {
    if (isMainTopic) {
      final top = Color.lerp(mainNoteTop, Colors.white, 0.38)!;
      final bottom = Color.lerp(noteBottom, Colors.white, 0.45)!;
      return BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [top, bottom],
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: noteBorder.withValues(alpha: 0.42)),
      );
    }

    final pane = filePaneGradient(topicAccent, fileType);
    final top = Color.lerp(pane.colors.first, Colors.white, 0.44)!;
    final bottom = Color.lerp(pane.colors.last, Colors.white, 0.5)!;
    return BoxDecoration(
      gradient: LinearGradient(
        begin: pane.begin,
        end: pane.end,
        colors: [top, bottom],
      ),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: topicPaneBorder(topicAccent, fileType).withValues(alpha: 0.38),
        width: filePaneBorderWidth,
      ),
    );
  }

  /// Topic-tinted pane surface — same pastel as topic canvas, used inside a card.
  @Deprecated('Use filePaneDecoration with a file type')
  static BoxDecoration topicPaneDecoration(
    Color accent, {
    bool isMain = false,
    String fileType = 'tasks',
  }) {
    return filePaneDecoration(accent, fileType, isMainTopic: isMain);
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
