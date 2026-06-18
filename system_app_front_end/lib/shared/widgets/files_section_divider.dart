import 'package:flutter/material.dart';

import '../../design_system/app_colors.dart';
import '../../design_system/app_icons.dart';
import '../../design_system/app_typography.dart';

/// Visual separator between main and secondary file sections.
class FilesSectionDivider extends StatelessWidget {
  const FilesSectionDivider({
    super.key,
    this.collapsed = false,
    this.onTap,
    this.compact = false,
  });

  final bool collapsed;
  final VoidCallback? onTap;
  final bool compact;

  static const _circleSize = 28.0;
  static const _iconSize = 14.0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 4 : 6),
      child: onTap == null
          ? const _SectionLine(fullWidth: true)
          : _DividerWithCenterButton(
              onTap: onTap!,
              child: collapsed
                  ? AppIcon(
                      AppIcons.more,
                      size: _iconSize,
                      color: AppColors.noteMeta,
                    )
                  : Text(
                      '−',
                      style: AppTypography.metaStyle.copyWith(
                        fontSize: _iconSize,
                        height: 1,
                        color: AppColors.noteMeta,
                      ),
                    ),
            ),
    );
  }
}

class _SectionLine extends StatelessWidget {
  const _SectionLine({this.fullWidth = false});

  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      width: fullWidth ? double.infinity : null,
      decoration: BoxDecoration(
        color: AppColors.text.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }
}

class _DividerWithCenterButton extends StatelessWidget {
  const _DividerWithCenterButton({
    required this.onTap,
    required this.child,
  });

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: _SectionLine()),
        const SizedBox(width: 10),
        Material(
          color: Colors.transparent,
          shape: CircleBorder(
            side: BorderSide(
              color: AppColors.noteBorder.withValues(alpha: 0.75),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: FilesSectionDivider._circleSize,
              height: FilesSectionDivider._circleSize,
              child: Center(child: child),
            ),
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(child: _SectionLine()),
      ],
    );
  }
}
