import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Compact teal switch used across the app.
class AppSwitch extends StatelessWidget {
  const AppSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: 0.78,
      alignment: Alignment.center,
      child: Switch(
        value: value,
        onChanged: onChanged,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        activeThumbColor: Colors.white,
        activeTrackColor: AppColors.primaryBright,
        inactiveThumbColor: Colors.white,
        inactiveTrackColor: AppColors.textHint.withValues(alpha: 0.28),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    );
  }
}
