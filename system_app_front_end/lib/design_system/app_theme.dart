import 'package:flutter/material.dart';

import '../core/l10n/app_language.dart';
import 'app_colors.dart';
import 'app_typography.dart';

ThemeData buildAppTheme(AppLanguage language) {
  AppTypography.configure(appLanguage: language);

  const seed = AppColors.primary;
  final scheme = ColorScheme.fromSeed(
    seedColor: seed,
    primary: AppColors.primary,
    surface: AppColors.canvasNeutralTop,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.canvasNeutralTop,
    textTheme: AppTypography.textTheme,
    dividerColor: AppColors.sidebarBorder,
    switchTheme: SwitchThemeData(
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return Colors.white.withValues(alpha: 0.72);
        }
        return Colors.white;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.primary;
        }
        if (states.contains(WidgetState.disabled)) {
          return AppColors.textHint.withValues(alpha: 0.18);
        }
        return AppColors.textHint.withValues(alpha: 0.28);
      }),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      overlayColor: WidgetStateProperty.all(AppColors.primary.withValues(alpha: 0.08)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.noteTop.withValues(alpha: 0.94),
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.14),
      surfaceTintColor: const Color(0xFFDDF6F2).withValues(alpha: 0.18),
      textStyle: AppTypography.metaStyle.copyWith(
        color: AppColors.text.withValues(alpha: 0.88),
        fontSize: 11,
        height: 1.2,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}
