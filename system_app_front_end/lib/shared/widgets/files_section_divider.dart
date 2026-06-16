import 'package:flutter/material.dart';

import '../../design_system/app_colors.dart';
import '../../design_system/app_icons.dart';

/// Visual separator between main and secondary file sections.
class FilesSectionDivider extends StatelessWidget {
  const FilesSectionDivider({
    super.key,
    this.collapsed = false,
    this.onTap,
    this.compact = false,
  });

  /// When true, shows a pressable more icon centered on the line.
  final bool collapsed;
  final VoidCallback? onTap;

  /// Tighter vertical padding for reorder-mode overlay.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 5 : 9),
      child: onTap == null
          ? const _SectionLine(fullWidth: true)
          : collapsed
          ? _CollapsedDivider(onTap: onTap!)
          : _ExpandedDivider(onTap: onTap!),
    );
  }
}

class _SectionLine extends StatelessWidget {
  const _SectionLine({this.fullWidth = false});

  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1.5,
      width: fullWidth ? double.infinity : null,
      decoration: BoxDecoration(
        color: AppColors.text.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }
}

class _CollapsedDivider extends StatelessWidget {
  const _CollapsedDivider({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _DividerWithCenterButton(
      onTap: onTap,
      child: const AppIcon(AppIcons.more, size: 16, color: AppColors.noteMeta),
    );
  }
}

class _ExpandedDivider extends StatelessWidget {
  const _ExpandedDivider({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _DividerWithCenterButton(
      onTap: onTap,
      child: Container(
        width: 12,
        height: 1.5,
        decoration: BoxDecoration(
          color: AppColors.noteMeta,
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    );
  }
}

class _DividerWithCenterButton extends StatelessWidget {
  const _DividerWithCenterButton({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: _SectionLine()),
        const SizedBox(width: 10),
        Material(
          color: AppColors.noteTop,
          shape: CircleBorder(
            side: BorderSide(
              color: AppColors.noteBorder.withValues(alpha: 0.95),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Padding(padding: EdgeInsets.all(6), child: child),
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(child: _SectionLine()),
      ],
    );
  }
}
