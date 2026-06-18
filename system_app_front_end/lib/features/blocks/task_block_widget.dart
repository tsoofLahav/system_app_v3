import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/models/task.dart';
import '../../shared/widgets/task_row.dart';

class TaskBlockWidget extends StatelessWidget {
  const TaskBlockWidget({
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
    return TaskRow(
      task: task,
      state: state,
      onToggle: onToggle,
    );
  }
}
