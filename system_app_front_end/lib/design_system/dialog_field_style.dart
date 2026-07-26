import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract final class DialogFieldStyle {
  static InputDecoration decoration({String? hintText}) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(
        color: AppColors.noteBorder.withValues(alpha: 0.68),
        width: 0.85,
      ),
    );
    return InputDecoration(
      hintText: hintText,
      isDense: true,
      filled: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(
          color: AppColors.primary.withValues(alpha: 0.54),
          width: 0.9,
        ),
      ),
      border: border,
    );
  }
}
