import 'package:flutter/material.dart';

import '../../design_system/app_colors.dart';
import '../../design_system/app_icons.dart';
import '../../design_system/app_typography.dart';

class GraphPlaceholderBlockWidget extends StatelessWidget {
  const GraphPlaceholderBlockWidget({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.noteBorder),
        borderRadius: BorderRadius.circular(8),
        color: AppColors.noteBottom.withValues(alpha: 0.45),
      ),
      child: Row(
        children: [
          const AppIcon(AppIcons.graph, size: 18, color: AppColors.textHint),
          const SizedBox(width: 8),
          Text(label, style: AppTypography.metaStyle),
        ],
      ),
    );
  }
}
