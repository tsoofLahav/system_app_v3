import 'package:flutter/material.dart';

import '../../ui/app_colors.dart';
import '../../ui/app_icons.dart';

/// Small outline mark for task completion — gentler than Material checkbox.
/// Always a square (equal width/height); corners stay tight so it reads as a
/// box, not a rounded bar. Pending uses a clock instead of a box; inactive
/// fills grey and is not pressable.
class TaskMark extends StatelessWidget {
  const TaskMark({
    super.key,
    required this.status,
    this.onToggle,
    this.size = 14,
    this.compact = false,
    this.accent = false,
  });

  final String status;
  final VoidCallback? onToggle;
  final double size;
  /// Tight tap target for dense rows — keeps a square hit box.
  final bool compact;
  final bool accent;

  bool get _done => status == 'done';
  bool get _inactive => status == 'inactive';
  bool get _pending => status == 'pending';

  @override
  Widget build(BuildContext context) {
    final side = compact ? size + 8 : 32.0;
    final child = _pending ? _clock() : _box();
    if (onToggle == null) {
      return SizedBox(
        width: side,
        height: side,
        child: Center(child: child),
      );
    }
    return SizedBox(
      width: side,
      height: side,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(side * 0.2),
          child: Center(child: child),
        ),
      ),
    );
  }

  Widget _clock() {
    return AppIcon(
      AppIcons.pending,
      size: size,
      color: AppColors.textHint,
    );
  }

  Widget _box() {
    final borderColor = _done
        ? AppColors.aiCyan.withValues(alpha: 0.65)
        : _inactive
            ? AppColors.textHint.withValues(alpha: 0.55)
            : accent
                ? AppColors.aiCyan.withValues(alpha: 0.55)
                : AppColors.noteBorder.withValues(alpha: 0.85);
    final corner = BorderRadius.circular(size * 0.15);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: corner,
        color: _done
            ? AppColors.aiCyan.withValues(alpha: 0.14)
            : _inactive
                ? AppColors.textHint.withValues(alpha: 0.28)
                : accent
                    ? AppColors.aiCyan.withValues(alpha: 0.08)
                    : Colors.transparent,
        border: Border.all(
          color: borderColor,
          width: 1,
        ),
      ),
      child: _done
          ? Icon(
              Icons.check_rounded,
              size: size - 4,
              color: AppColors.aiCyan.withValues(alpha: 0.92),
            )
          : null,
    );
  }
}
