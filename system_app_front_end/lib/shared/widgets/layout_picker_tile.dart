import 'package:flutter/material.dart';

import '../../design_system/app_colors.dart';
import '../../design_system/app_typography.dart';
import '../../design_system/layout_preview_icon.dart';

class LayoutPickerTile extends StatelessWidget {
  const LayoutPickerTile({
    super.key,
    required this.layoutId,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
    this.compact = false,
    this.iconWidth = 56,
    this.iconHeight = 40,
    this.focused = false,
  });

  final String layoutId;
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;
  final bool compact;
  final double iconWidth;
  final double iconHeight;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: EdgeInsets.all(compact ? 4 : 6),
            child: DecoratedBox(
              decoration: focused
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.primaryBright.withValues(alpha: 0.72),
                        width: 1.2,
                      ),
                    )
                  : const BoxDecoration(),
              child: Padding(
                padding: focused ? const EdgeInsets.all(2) : EdgeInsets.zero,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LayoutPreviewIcon(
                      layoutId: layoutId,
                      selected: selected,
                      enabled: enabled,
                      width: iconWidth,
                      height: iconHeight,
                    ),
                    if (!compact) ...[
                      const SizedBox(height: 6),
                      SizedBox(
                        width: 72,
                        child: Text(
                          label,
                          style: AppTypography.metaStyle.copyWith(
                            fontSize: 10,
                            color: enabled
                                ? (selected
                                    ? AppColors.primaryBright.withValues(
                                        alpha: 0.96,
                                      )
                                    : AppColors.text.withValues(alpha: 0.72))
                                : AppColors.textHint.withValues(alpha: 0.45),
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
