import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/models/task.dart';
import '../../design_system/app_colors.dart';
import '../../design_system/app_typography.dart';
import '../../shared/widgets/task_assign_menu.dart';

class TaskRow extends StatelessWidget {
  const TaskRow({
    super.key,
    required this.task,
    required this.state,
    required this.onToggle,
  });

  final Task task;
  final AppState state;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onSecondaryTapDown: (details) => showTaskAssignMenu(
          context: context,
          globalPosition: details.globalPosition,
          task: task,
          state: state,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Checkbox(
                value: task.isDone,
                onChanged: (_) => onToggle(),
              ),
              Expanded(
                child: Text(
                  task.title,
                  style: AppTypography.noteBodyStyle.copyWith(
                    decoration: task.isDone ? TextDecoration.lineThrough : null,
                    color: task.isDone
                        ? AppColors.text.withValues(alpha: 0.45)
                        : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
