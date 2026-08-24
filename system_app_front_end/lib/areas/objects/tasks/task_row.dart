import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../files/rich_text/formatted_text_field.dart';
import '../../files/rich_text/span_text_editing_controller.dart';
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
    this.onEnter,
    this.onBackspaceAtStart,
    this.onSecondaryTapDown,
    this.readOnly = false,
    this.toggleEnabled = true,
    this.autofocus = false,
    this.onAutofocusConsumed,
  });

  final Task task;
  final AppState state;
  final VoidCallback onToggle;
  final Future<void> Function()? onDelete;
  final ValueChanged<String>? onTitleChanged;

  /// Enter in the title field — create next / exit when empty final.
  final Future<void> Function(String title)? onEnter;

  /// Backspace on an empty title — delete / remove the row.
  final Future<void> Function()? onBackspaceAtStart;
  final GestureTapDownCallback? onSecondaryTapDown;
  final bool readOnly;
  final bool toggleEnabled;
  final bool autofocus;
  final VoidCallback? onAutofocusConsumed;

  @override
  State<TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends State<TaskRow> {
  late final SpanTextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = SpanTextEditingController(text: widget.task.title);
    _focusNode = FocusNode();
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _focusNode.requestFocus();
        widget.onAutofocusConsumed?.call();
      });
    }
  }

  @override
  void didUpdateWidget(TaskRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task.id != widget.task.id ||
        (oldWidget.task.title != widget.task.title && !_focusNode.hasFocus)) {
      _controller.text = widget.task.title;
    }
    if (widget.autofocus && !oldWidget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _focusNode.requestFocus();
        widget.onAutofocusConsumed?.call();
      });
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final done = widget.task.isDone;
    final titleStyle = AppTypography.taskRowStyle.copyWith(
      decoration: done ? TextDecoration.lineThrough : null,
      color: done ? AppColors.textHint : null,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            // Nudge the compact mark down to the first-line text center.
            padding: const EdgeInsets.only(top: 2),
            child: TaskMark(
              done: done,
              compact: true,
              onToggle: widget.toggleEnabled && !widget.readOnly
                  ? widget.onToggle
                  : () {},
            ),
          ),
          Expanded(
            child: FormattedTextField(
              controller: _controller,
              focusNode: _focusNode,
              style: titleStyle,
              maxLines: null,
              minLines: 1,
              textAlignVertical: TextAlignVertical.center,
              onChanged: widget.readOnly ? null : widget.onTitleChanged,
              onEnter: widget.onEnter == null || widget.readOnly
                  ? null
                  : () => widget.onEnter!(_controller.text),
              onBackspaceAtStart:
                  widget.readOnly ? null : widget.onBackspaceAtStart,
              onSecondaryTapDown: widget.onSecondaryTapDown,
            ),
          ),
        ],
      ),
    );
  }
}
