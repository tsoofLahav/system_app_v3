import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_typography.dart';

class AppSegmentedOption<T> {
  const AppSegmentedOption({required this.value, required this.label});

  final T value;
  final String label;
}

/// Compact framed segmented toggle — each option in its own outlined chip.
class AppSegmentedToggle<T> extends StatelessWidget {
  const AppSegmentedToggle({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.enabled = true,
  });

  final List<AppSegmentedOption<T>> options;
  final T? selected;
  final ValueChanged<T>? onSelected;
  final bool enabled;

  static const _horizontalPadding = 10.0;
  static const _verticalPadding = 5.0;
  static const _gap = 6.0;
  static const _radius = 6.0;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: _gap,
      runSpacing: _gap,
      children: [
        for (final option in options)
          _SegmentChip(
            label: option.label,
            selected: selected != null && option.value == selected,
            enabled: enabled && onSelected != null,
            onTap: enabled && onSelected != null
                ? () {
                    if (option.value != selected) onSelected!(option.value);
                  }
                : null,
          ),
      ],
    );
  }
}

class _SegmentChip extends StatelessWidget {
  const _SegmentChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final borderColor = selected
        ? AppColors.primary.withValues(alpha: 0.55)
        : AppColors.noteBorder.withValues(alpha: 0.42);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(AppSegmentedToggle._radius),
        child: Ink(
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primaryBright.withValues(alpha: 0.92)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppSegmentedToggle._radius),
            border: Border.all(color: borderColor, width: 0.8),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSegmentedToggle._horizontalPadding,
            vertical: AppSegmentedToggle._verticalPadding,
          ),
          child: Text(
            label,
            style: AppTypography.metaStyle.copyWith(
              fontSize: 11.5,
              height: 1.15,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: !enabled
                  ? AppColors.textHint.withValues(alpha: 0.55)
                  : selected
                  ? Colors.white.withValues(alpha: 0.96)
                  : AppColors.text.withValues(alpha: 0.82),
            ),
          ),
        ),
      ),
    );
  }
}
