import 'package:flutter/material.dart';

import '../../design_system/app_colors.dart';

/// Small outline mark for task completion — gentler than Material checkbox.
class TaskMark extends StatelessWidget {
  const TaskMark({
    super.key,
    required this.done,
    required this.onToggle,
    this.size = 14,
  });

  final bool done;
  final VoidCallback onToggle;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 32,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(6),
          child: Center(
            child: AnimatedContainer(
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
            ),
          ),
        ),
      ),
    );
  }
}
