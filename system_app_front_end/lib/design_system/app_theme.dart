import 'package:flutter/material.dart';

import '../core/l10n/app_language.dart';
import 'app_colors.dart';
import 'app_typography.dart';

ThemeData buildAppTheme(AppLanguage language) {
  AppTypography.configure(appLanguage: language);

  const seed = Color(0xFF6B7280);
  final scheme = ColorScheme.fromSeed(
    seedColor: seed,
    surface: AppColors.canvasNeutralTop,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.canvasNeutralTop,
    textTheme: AppTypography.textTheme,
    dividerColor: AppColors.sidebarBorder,
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.noteTop.withValues(alpha: 0.94),
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.14),
      surfaceTintColor: const Color(0xFFDDF6F2).withValues(alpha: 0.18),
      textStyle: AppTypography.metaStyle.copyWith(
        color: AppColors.text.withValues(alpha: 0.92),
        fontSize: 12,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}
