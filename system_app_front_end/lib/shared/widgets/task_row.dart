import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_state.dart';
import '../../core/models/task.dart';
import '../../design_system/app_colors.dart';
import '../../design_system/app_typography.dart';
import 'task_mark.dart';

typedef BlockMenuHandler = Future<void> Function(String action);

class TaskRow extends StatefulWidget {
  const TaskRow({
    super.key,
    required this.task,
    required this.state,
    required this.onToggle,
    this.onDelete,
    this.onTitleChanged,
    this.readOnly = false,
    this.toggleEnabled = true,
  });

  final Task task;
  final AppState state;
  final VoidCallback onToggle;
  final Future<void> Function()? onDelete;
  final ValueChanged<String>? onTitleChanged;
  final bool readOnly;
  final bool toggleEnabled;

  @override
  State<TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends State<TaskRow> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.task.title);
  }

  @override
  void didUpdateWidget(TaskRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task.id != widget.task.id ||
        oldWidget.task.title != widget.task.title) {
      _controller.text = widget.task.title;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TaskMark(
          done: task.isDone,
          onToggle: widget.onToggle,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: widget.readOnly
              ? Text(
                  task.title,
                  style: AppTypography.noteBodyStyle.copyWith(
                    decoration: task.isDone ? TextDecoration.lineThrough : null,
                    color: task.isDone ? AppColors.textHint : AppColors.text,
                  ),
                )
              : TextField(
                  controller: _controller,
                  maxLines: null,
                  style: AppTypography.noteBodyStyle.copyWith(
                    decoration: task.isDone ? TextDecoration.lineThrough : null,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onSubmitted: widget.onTitleChanged,
                  onEditingComplete: () => widget.onTitleChanged?.call(_controller.text),
                ),
        ),
        if (widget.onDelete != null && !widget.readOnly)
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            onPressed: widget.onDelete,
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }
}
