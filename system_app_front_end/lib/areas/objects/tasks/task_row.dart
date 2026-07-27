import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../data/task.dart';
import '../../ui/app_colors.dart';
import '../../ui/app_typography.dart';
import './task_mark.dart';

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
    final done = widget.task.isDone;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TaskMark(
            done: done,
            onToggle: widget.toggleEnabled && !widget.readOnly
                ? widget.onToggle
                : () {},
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _controller,
              readOnly: widget.readOnly,
              style: AppTypography.noteBodyStyle.copyWith(
                decoration: done ? TextDecoration.lineThrough : null,
                color: done ? AppColors.textHint : null,
              ),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
              ),
              onSubmitted: widget.onTitleChanged,
              onEditingComplete: () =>
                  widget.onTitleChanged?.call(_controller.text),
            ),
          ),
          if (widget.onDelete != null && !widget.readOnly)
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: widget.onDelete,
            ),
        ],
      ),
    );
  }
}
