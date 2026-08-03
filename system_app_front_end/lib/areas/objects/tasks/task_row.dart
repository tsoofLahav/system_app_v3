import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.task.title);
    _focusNode = FocusNode(onKeyEvent: _onKeyEvent);
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

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (widget.readOnly || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final isEnter = event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (isEnter && !HardwareKeyboard.instance.isShiftPressed) {
      if (widget.onEnter != null) {
        widget.onEnter!(_controller.text);
        return KeyEventResult.handled;
      }
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace &&
        widget.onBackspaceAtStart != null &&
        _controller.text.isEmpty) {
      widget.onBackspaceAtStart!();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final done = widget.task.isDone;
    final field = TextField(
      controller: _controller,
      focusNode: _focusNode,
      readOnly: widget.readOnly,
      style: AppTypography.noteBodyStyle.copyWith(
        decoration: done ? TextDecoration.lineThrough : null,
        color: done ? AppColors.textHint : null,
      ),
      decoration: InputDecoration(
        isDense: true,
        border: InputBorder.none,
        hintText: widget.state.strings['newTaskHint'],
        hintStyle: AppTypography.noteBodyStyle.copyWith(
          color: AppColors.textHint.withValues(alpha: 0.55),
        ),
      ),
      maxLines: null,
      minLines: 1,
      textInputAction: TextInputAction.newline,
      onChanged: widget.onTitleChanged,
    );

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
            child: widget.onSecondaryTapDown == null
                ? field
                : GestureDetector(
                    onSecondaryTapDown: widget.onSecondaryTapDown,
                    child: field,
                  ),
          ),
        ],
      ),
    );
  }
}
