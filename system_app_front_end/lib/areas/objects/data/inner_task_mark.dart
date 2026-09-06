import 'package:flutter/material.dart';

import '../../ui/app_colors.dart';
import '../../ui/app_icons.dart';

/// Circular checklist mark for info inner tasks — not [TaskMark].
///
/// Square cyan boxes are real tasks; these stay round and quieter so the two
/// never read as the same control.
class InnerTaskMark extends StatelessWidget {
  const InnerTaskMark({
    super.key,
    required this.done,
    this.onToggle,
    this.size = 14,
  });

  final bool done;
  final VoidCallback? onToggle;
  final double size;

  static const _doneFill = Color(0xFF7A9E80);
  static const _doneRing = Color(0xFF6B8F71);

  @override
  Widget build(BuildContext context) {
    final hit = size + 10;
    final child = _circle();
    if (onToggle == null) {
      return SizedBox(width: hit, height: hit, child: Center(child: child));
    }
    return SizedBox(
      width: hit,
      height: hit,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onToggle,
          customBorder: const CircleBorder(),
          child: Center(child: child),
        ),
      ),
    );
  }

  Widget _circle() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? _doneFill.withValues(alpha: 0.18) : Colors.transparent,
        border: Border.all(
          color: done
              ? _doneRing.withValues(alpha: 0.9)
              : AppColors.noteBorder.withValues(alpha: 0.95),
          width: 1.15,
        ),
      ),
      child: done
          ? Center(
              child: AppIcon(
                AppIcons.check,
                size: size - 4,
                color: _doneRing.withValues(alpha: 0.95),
              ),
            )
          : null,
    );
  }
}
