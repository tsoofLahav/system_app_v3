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

  /// App primary accent — teal-blue used for toggles, selections, and key actions.
  static const primary = Color(0xFF37899E);
  static const primaryLight = Color(0xFF51A0B0);

  /// Brighter teal fill for segmented toggles and active controls.
  static const primaryBright = Color(0xFF58C4D8);

  /// Amber-brown for menu entries that delete or discard. Never red — nothing
  /// in a personal workspace deserves an alarm.
  static const destructive = Color(0xFFB45309);

  /// Frost behind glass — dialogs, the sidebar, floating chrome. Faintly cyan,
  /// which is what makes a blurred panel read as glass rather than as fog.
  static const glassTint = Color(0xFFDDF6F2);

  /// Frost behind a context menu. Cooler and greyer than [glassTint], so a menu
  /// over a dialog still reads as sitting on top of it.
  static const menuTint = Color(0xFFF4F4F5);

  /// Environmental background — always neutral under everything else.
  static const neutralCanvasGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [canvasNeutralTop, canvasNeutralBottom],
  );

  /// Soft topic wash from the top of the window.
  ///
  /// Painted full-bleed behind the sidebar and the bottom bar so the topic
  /// colour reads as the room, while chrome floats above it.
  static LinearGradient topicTopVeil({
    required Color accent,
    required bool isMainTopic,
  }) {
    final tint = Color.alphaBlend(
      (isMainTopic ? text : accent).withValues(
        alpha: isMainTopic ? 0.02 : 0.08,
      ),
      Colors.white,
    );
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        tint.withValues(alpha: 0.86),
        tint.withValues(alpha: 0.52),
        tint.withValues(alpha: 0),
      ],
      stops: const [0, 0.22, 0.55],
    );
  }

  /// Desaturated topic accent for pane fills (borders use [topicPaneBorder]).
  static Color uiAccent(Color accent) =>
      Color.lerp(accent, Colors.white, 0.18) ?? accent;

  /// Vivid topic accent for pane outlines.
  static Color topicPaneBorder(Color topicAccent, int fileId) {
    final vivid = Color.lerp(topicAccent, Colors.white, 0.08) ?? topicAccent;
    final alpha = 0.36 + fileTintStrength(fileId) * 0.42;
    return vivid.withValues(alpha: alpha.clamp(0.0, 1.0));
  }

  /// Lightest and heaviest a file pane wears its topic color.
  static const minFileTint = 0.045;
  static const maxFileTint = 0.17;

  /// How strongly one file wears its topic color.
  ///
  /// Panes in a topic should differ enough to tell apart at a glance, so the
  /// strength is spread across the range rather than shared. It is derived from
  /// the file's id, which makes it arbitrary but **fixed**: a file keeps its
  /// shade when the topic is rearranged, reopened, or opened on another device.
  static double fileTintStrength(int fileId) {
    // Knuth multiplicative hash — spreads consecutive ids, unlike `id % n`.
    final spread = (fileId * 2654435761) & 0x7FFFFFFF;
    final position = (spread % 1000) / 1000.0;
    return minFileTint + position * (maxFileTint - minFileTint);
  }

  static const filePaneBorderWidth = 0.5;

  static LinearGradient filePaneGradient(Color topicAccent, int fileId) {
    final accent = uiAccent(topicAccent);
    final strength = fileTintStrength(fileId);
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

  /// File pane wearing its topic's color (the main topic stays white).
  static BoxDecoration filePaneDecoration(
    Color topicAccent,
    int fileId, {
    bool isMainTopic = false,
  }) {
    if (isMainTopic) return mainNoteDecoration();
    return BoxDecoration(
      gradient: filePaneGradient(topicAccent, fileId),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(
        color: topicPaneBorder(topicAccent, fileId),
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
    int fileId, {
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

    final pane = filePaneGradient(topicAccent, fileId);
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
        color: topicPaneBorder(topicAccent, fileId).withValues(alpha: 0.38),
        width: filePaneBorderWidth,
      ),
    );
  }

  /// Faint frame for reusable details blocks (title + body unit).
  static BoxDecoration detailsBlockDecoration() {
    return BoxDecoration(
      color: noteTop.withValues(alpha: 0.42),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: noteBorder.withValues(alpha: 0.56),
        width: 0.85,
      ),
    );
  }

  /// In-file info embed: very light topic wash + thin topic outline.
  static BoxDecoration infoBlockDecoration(Color topicAccent) {
    final wash = Color.lerp(topicAccent, Colors.white, 0.92) ?? topicAccent;
    return BoxDecoration(
      color: wash.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: topicAccent.withValues(alpha: 0.42),
        width: 0.85,
      ),
    );
  }

  /// `#RRGGBB` (uppercase). Invalid / empty → [text].
  static Color colorFromHex(String? hex) {
    return tryParseHex(hex) ?? text;
  }

  static Color? tryParseHex(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    var v = hex.trim().replaceFirst('#', '');
    if (v.length == 3) {
      v = '${v[0]}${v[0]}${v[1]}${v[1]}${v[2]}${v[2]}';
    }
    if (v.length != 6) return null;
    final value = int.tryParse(v, radix: 16);
    if (value == null) return null;
    return Color(0xFF000000 | value);
  }

  static String colorToHex(Color color) {
    final rgb = color.toARGB32() & 0xFFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  static String normalizeHex(String hex) => colorToHex(colorFromHex(hex));
}

/// The one spacing scale. Small steps, because the app is dense on purpose.
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
