import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/l10n/app_language.dart';
import 'app_colors.dart';

/// One font family, restrained weights, one soft text color.
abstract final class AppTypography {
  static const FontWeight weight = FontWeight.w400;
  static const FontWeight titleWeight = FontWeight.w500;
  static AppLanguage language = AppLanguage.en;

  static void configure({required AppLanguage appLanguage}) {
    language = appLanguage;
  }

  static TextStyle _style({
    required double size,
    Color? color,
    double height = 1.5,
    double? letterSpacing,
    FontWeight? fontWeight,
    TextDecoration? decoration,
  }) {
    if (language == AppLanguage.he) {
      return TextStyle(
        fontFamily: 'SF Hebrew',
        fontFamilyFallback: const [
          '.SF Hebrew',
          'Arial Hebrew',
          'Noto Sans Hebrew',
          'Helvetica Neue',
        ],
        fontSize: size,
        fontWeight: fontWeight ?? weight,
        color: color ?? AppColors.text,
        height: height,
        letterSpacing: letterSpacing,
        decoration: decoration,
      );
    }

    return GoogleFonts.inter(
      fontSize: size,
      fontWeight: fontWeight ?? weight,
      color: color ?? AppColors.text,
      height: height,
      letterSpacing: letterSpacing,
      decoration: decoration,
    );
  }

  /// Topic / page title in main pane header.
  static TextStyle get pageTitleStyle => _style(
    size: 19,
    height: 1.3,
    letterSpacing: language == AppLanguage.he ? 0 : -0.2,
    fontWeight: titleWeight,
  );

  /// File note name on each card.
  static TextStyle get noteTitleStyle => _style(
    size: 14,
    height: 1.3,
    letterSpacing: language == AppLanguage.he ? 0 : -0.1,
    fontWeight: titleWeight,
  );

  /// Section headers inside file content.
  static TextStyle get blockHeaderStyle =>
      _style(size: 14, height: 1.4, fontWeight: FontWeight.w600);

  /// Body, inputs, tasks, checklist items — smaller.
  static TextStyle get noteBodyStyle => _style(size: 12.5, height: 1.55);

  /// Dense list bullets and list item fields.
  static TextStyle get listItemStyle => _style(size: 12.5, height: 1.38);

  /// Task rows in files and task views.
  static TextStyle get taskRowStyle => _style(size: 12.5, height: 1.38);

  static double get taskRowLineHeight {
    final style = taskRowStyle;
    return (style.fontSize ?? 12.5) * (style.height ?? 1.38);
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
