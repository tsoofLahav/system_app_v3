import 'package:flutter/material.dart';

import '../../ui/app_colors.dart';

/// Small outline mark for task completion — gentler than Material checkbox.
/// Always a square (equal width/height); corners stay tight so it reads as a
/// box, not a rounded bar.
class TaskMark extends StatelessWidget {
  const TaskMark({
    super.key,
    required this.done,
    this.onToggle,
    this.size = 14,
    this.compact = false,
    this.accent = false,
  });

  final bool done;
  final VoidCallback? onToggle;
  final double size;
  /// Tight tap target for dense rows — keeps a square hit box.
  final bool compact;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final borderColor = done
        ? AppColors.aiCyan.withValues(alpha: 0.65)
        : accent
            ? AppColors.aiCyan.withValues(alpha: 0.55)
            : AppColors.noteBorder.withValues(alpha: 0.85);
    // Slight radius only — larger values make a 14px mark look pill/rectangular.
    final corner = BorderRadius.circular(size * 0.15);

    final mark = AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: corner,
        color: done
            ? AppColors.aiCyan.withValues(alpha: 0.14)
            : accent
                ? AppColors.aiCyan.withValues(alpha: 0.08)
                : Colors.transparent,
        border: Border.all(
          color: borderColor,
          width: 1,
        ),
      ),
      child: done
          ? Icon(
              Icons.check_rounded,
              size: size - 4,
              color: AppColors.aiCyan.withValues(alpha: 0.92),
            )
          : null,
    );

    final side = compact ? size + 8 : 32.0;

    return SizedBox(
      width: side,
      height: side,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(side * 0.2),
          child: Center(child: mark),
        ),
      ),
    );
  }
}
