import 'package:flutter/material.dart';

import '../../design_system/app_colors.dart';

/// Small outline mark for task completion — gentler than Material checkbox.
class TaskMark extends StatelessWidget {
  const TaskMark({
    super.key,
    required this.done,
    required this.onToggle,
    this.size = 14,
    this.compact = false,
  });

  final bool done;
  final VoidCallback onToggle;
  final double size;
  /// Tight tap target for [TaskRow] — avoids 32×32 box pushing below text.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final mark = AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        color: done
            ? AppColors.aiCyan.withValues(alpha: 0.14)
            : Colors.transparent,
        border: Border.all(
          color: done
              ? AppColors.aiCyan.withValues(alpha: 0.65)
              : AppColors.noteBorder.withValues(alpha: 0.85),
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

    final ink = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(6),
        child: compact
            ? Padding(padding: const EdgeInsets.all(2), child: mark)
            : Center(child: mark),
      ),
    );

    if (compact) return ink;

    return SizedBox(
      width: 32,
      height: 32,
      child: ink,
    );
  }
}
