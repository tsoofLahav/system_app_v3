import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_state.dart';
import '../../core/models/block.dart';
import '../../core/models/task.dart';
import '../../design_system/app_colors.dart';
import '../../design_system/app_typography.dart';
import '../../features/blocks/list_text_parse.dart';
import '../../shared/widgets/task_assign_menu.dart';
import '../../features/blocks/formatted_text_field.dart';
import 'task_mark.dart';

class TaskRow extends StatefulWidget {
  const TaskRow({
    super.key,
    required this.task,
    required this.state,
    required this.onToggle,
    this.taskBlock,
    this.onDelete,
    this.onTitleChanged,
    this.onAddTaskAfter,
    this.allTaskTitles,
    this.onPasteLines,
    this.autofocus = false,
    this.onAutofocused,
  });

  final Task task;
  final AppState state;
  final VoidCallback onToggle;
  final Block? taskBlock;
  final VoidCallback? onDelete;
  final ValueChanged<String>? onTitleChanged;
  final VoidCallback? onAddTaskAfter;
  final List<String>? allTaskTitles;
  final Future<void> Function(List<String> lines)? onPasteLines;
  final bool autofocus;
  final VoidCallback? onAutofocused;

  @override
  State<TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends State<TaskRow> {
  late final TextEditingController _controller;
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.task.title);
    _requestAutofocus();
  }

  @override
  void didUpdateWidget(TaskRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task.id != widget.task.id &&
        _controller.text != widget.task.title) {
      _controller.text = widget.task.title;
    }
    _requestAutofocus();
  }

  void _requestAutofocus() {
    if (!widget.autofocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
      _controller.selection = const TextSelection.collapsed(offset: 0);
      widget.onAutofocused?.call();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _handlePaste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final raw = data?.text;
    if (raw == null || raw.isEmpty || widget.onPasteLines == null) return;
    final lines = parsePastedListText(raw);
    if (lines.isEmpty) return;
    if (lines.length == 1) {
      _controller.text = lines.first;
      widget.onTitleChanged?.call(lines.first);
      return;
    }
    _controller.text = lines.first;
    widget.onTitleChanged?.call(lines.first);
    await widget.onPasteLines!(lines.sublist(1));
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onSecondaryTapDown: (details) => showTaskAssignMenu(
          context: context,
          globalPosition: details.globalPosition,
          task: widget.task,
          state: widget.state,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Focus(
            onKeyEvent: (_, event) {
              if (event is! KeyDownEvent) return KeyEventResult.ignored;
              final isMeta = HardwareKeyboard.instance.isMetaPressed;
              if (isMeta && event.logicalKey == LogicalKeyboardKey.keyA) {
                final titles = widget.allTaskTitles;
                if (titles != null && titles.isNotEmpty) {
                  Clipboard.setData(
                    ClipboardData(text: titles.join('\n')),
                  );
                }
                return KeyEventResult.handled;
              }
              if (isMeta && event.logicalKey == LogicalKeyboardKey.keyV) {
                _handlePaste();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: TaskMark(done: widget.task.isDone, onToggle: widget.onToggle),
                ),
                Expanded(
                  child: FormattedTextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    style: AppTypography.taskRowStyle.copyWith(
                      decoration: widget.task.isDone
                          ? TextDecoration.lineThrough
                          : null,
                      color: widget.task.isDone
                          ? AppColors.text.withValues(alpha: 0.45)
                          : null,
                    ),
                    maxLines: null,
                    minLines: 1,
                    stripNewlines: true,
                    onChanged: (v) => widget.onTitleChanged?.call(v),
                    onEnter: widget.onAddTaskAfter,
                    onBackspaceAtStart: () {
                      if (_controller.text.isEmpty) {
                        widget.onDelete?.call();
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
