import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/document_text_size.dart';
import '../../core/l10n/app_language.dart';
import './app_colors.dart';

/// One font family, restrained weights, one soft text color.
abstract final class AppTypography {
  static const FontWeight weight = FontWeight.w400;
  static const FontWeight titleWeight = FontWeight.w500;
  static AppLanguage language = AppLanguage.en;
  static DocumentTextSize documentTextSize = DocumentTextSize.platformDefault;

  static void configure({
    required AppLanguage appLanguage,
    DocumentTextSize? textSize,
  }) {
    language = appLanguage;
    if (textSize != null) documentTextSize = textSize;
  }

  static double get documentBodySize => documentTextSize.points;

  /// Color-emoji faces last so layout and paint share the same emoji metrics.
  /// Without this, a Hebrew/Inter run + emoji shifts the selection wash.
  static const List<String> _emojiFallback = [
    'Apple Color Emoji',
    'Noto Color Emoji',
    'Segoe UI Emoji',
  ];

  static TextStyle _style({
    required double size,
    Color? color,
    double height = 1.5,
    double? letterSpacing,
    FontWeight? fontWeight,
    TextDecoration? decoration,
  }) {
    // Hebrew uses the system SF Hebrew face (with fallbacks), matching v1.
    // Letter spacing is always 0 — negative tracking mangles Hebrew glyphs.
    // Styles must be read per build, never cached as `static final`, or a
    // language switch leaves Inter under Hebrew text.
    if (language == AppLanguage.he) {
      return TextStyle(
        fontFamily: 'SF Hebrew',
        fontFamilyFallback: const [
          '.SF Hebrew',
          'Arial Hebrew',
          'Noto Sans Hebrew',
          'Helvetica Neue',
          ..._emojiFallback,
        ],
        fontSize: size,
        fontWeight: fontWeight ?? weight,
        color: color ?? AppColors.text,
        height: height,
        letterSpacing: 0,
        decoration: decoration,
      );
    }

    final inter = GoogleFonts.inter(
      fontSize: size,
      fontWeight: fontWeight ?? weight,
      color: color ?? AppColors.text,
      height: height,
      letterSpacing: letterSpacing,
      decoration: decoration,
    );
    return inter.copyWith(
      fontFamilyFallback: [...?inter.fontFamilyFallback, ..._emojiFallback],
    );
  }

  /// Topic / page title in main pane header.
  static TextStyle get pageTitleStyle => _style(
    size: 19,
    height: 1.3,
    letterSpacing: -0.2,
    fontWeight: titleWeight,
  );

  /// File note name on each card.
  static TextStyle get noteTitleStyle => _style(
    size: 14,
    height: 1.3,
    letterSpacing: -0.1,
    fontWeight: titleWeight,
  );

  /// Section headers inside file content.
  static TextStyle get blockHeaderStyle =>
      _style(size: 14, height: 1.4, fontWeight: FontWeight.w600);

  /// Body, inputs, tasks, checklist items — follows [documentTextSize].
  static TextStyle get noteBodyStyle =>
      _style(size: documentBodySize, height: 1.55);

  /// A paragraph as it reads inside a document — tighter than a bare body
  /// line, because paragraphs sit one under another with almost no gap.
  static TextStyle get documentParagraphStyle =>
      noteBodyStyle.copyWith(height: 1.35);

  /// A heading inside a document. Level 1 is the largest; each level down
  /// loses 2px. Sizes stay relative to the chosen body size.
  static TextStyle documentHeadingStyle(int level) {
    final clamped = level.clamp(1, 5);
    return noteTitleStyle.copyWith(
      fontSize: documentBodySize + 11.5 - clamped * 2,
      height: 1.3,
      fontWeight: FontWeight.w600,
    );
  }

  /// Dense list bullets and list item fields.
  static TextStyle get listItemStyle =>
      _style(size: documentBodySize, height: 1.38);

  /// Task rows in files and task views.
  static TextStyle get taskRowStyle =>
      _style(size: documentBodySize, height: 1.38);

  static double get taskRowLineHeight {
    final style = taskRowStyle;
    return (style.fontSize ?? documentBodySize) * (style.height ?? 1.38);
  }

  /// Locks line height to [style] so color-emoji fallbacks do not shift
  /// lines that have no emoji (selection wash would sit off the glyphs).
  static StrutStyle fieldStrut(TextStyle style) {
    return StrutStyle.fromTextStyle(style, forceStrutHeight: true);
  }

  /// Secondary labels (sidebar sections, meta).
  static TextStyle get metaStyle =>
      _style(size: 12, color: AppColors.textHint, height: 1.4);

  /// Sidebar section headers (Projects, Processes, Areas).
  static TextStyle get sidebarSectionStyle => _style(size: 13, height: 1.35);

  /// Sidebar topic rows — smaller than section headers.
  static TextStyle get sidebarItemStyle => _style(size: 11, height: 1.4);

  static TextTheme get textTheme => TextTheme(
    headlineSmall: pageTitleStyle,
    titleMedium: noteTitleStyle,
    titleSmall: metaStyle,
    bodyLarge: noteBodyStyle,
    bodyMedium: noteBodyStyle,
    labelLarge: noteTitleStyle,
  );

  static InputDecoration noteInputDecoration({String? hint, double? fontSize}) {
    final size = fontSize ?? 12;
    return InputDecoration(
      border: InputBorder.none,
      isDense: true,
      contentPadding: EdgeInsets.zero,
      hintText: hint,
      hintStyle: _style(size: size, color: AppColors.textHint),
    );
  }
}
