import 'package:flutter/material.dart';

import '../../core/models/app_file.dart';
import '../../core/app_state.dart';
import '../../core/models/block.dart';
import '../../core/models/task.dart';
import '../../core/models/task_view_menu_context.dart';
import '../../design_system/app_typography.dart';
import '../../features/blocks/formatted_text_field.dart';
import '../../core/registry/automation_flow_registry.dart';
import '../../features/shell/automation_abandon_dialog.dart';
import '../../shared/widgets/task_row.dart';
import '../blocks/block_context_menu.dart';

/// One zone (active or done): a [TaskRow] per task plus a draft row at the bottom.
class TaskZoneList extends StatefulWidget {
  const TaskZoneList({
    super.key,
    required this.tasks,
    required this.done,
    required this.state,
    required this.onCreateAfter,
    required this.onCreateAtEnd,
    required this.onTitleChanged,
    required this.onDelete,
    required this.onPasteAfter,
    this.contextMenuFileType,
    this.contextMenuTargetBlock,
    this.onBlockMenuAction,
    this.readOnlyTaskRefs = false,
    this.onReadOnlyAction,
    this.viewMenuContext,
    this.focusTaskId,
    this.onFocusHandled,
    this.file,
  });

  final List<Task> tasks;
  final bool done;
  final AppState state;
  final AppFile? file;
  final Future<void> Function(Task? afterTask, Offset position) onCreateAfter;
  final Future<void> Function(String title, Offset position) onCreateAtEnd;
  final Future<void> Function(Task task, String title) onTitleChanged;
  final Future<void> Function(Task task) onDelete;
  final Future<void> Function(
    Task afterTask,
    List<String> lines,
    Offset position,
  )
  onPasteAfter;
  final String? contextMenuFileType;
  final Block? contextMenuTargetBlock;
  final BlockMenuHandler? onBlockMenuAction;
  final bool readOnlyTaskRefs;
  final VoidCallback? onReadOnlyAction;
  final TaskViewMenuContext? viewMenuContext;
  final int? focusTaskId;
  final VoidCallback? onFocusHandled;

  @override
  State<TaskZoneList> createState() => _TaskZoneListState();
}

class _TaskZoneListState extends State<TaskZoneList> {
  @override
  Widget build(BuildContext context) {
    final titles = widget.tasks.map((task) => task.title).toList();
    final hideDraft =
        widget.readOnlyTaskRefs ||
        widget.tasks.any((task) => task.isAutomationsTopic);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final task in widget.tasks)
          TaskRow(
            key: ValueKey(task.id),
            task: task,
            state: widget.state,
            taskBlock: widget.file != null
                ? widget.state.taskRowBlockInFile(widget.file!, task)
                : null,
            onToggle: () => widget.state.toggleTaskStatus(
              task,
              confirmAbandonCompanionFlow: () =>
                  showAutomationAbandonChangesDialog(
                    context: context,
                    state: widget.state,
                  ),
            ),
            onTitleChanged: widget.readOnlyTaskRefs
                ? null
                : (title) => widget.onTitleChanged(task, title),
            onDelete: widget.readOnlyTaskRefs || task.isAutomationTrigger
                ? null
                : () => widget.onDelete(task),
            onAddTaskAfter: widget.readOnlyTaskRefs
                ? null
                : (position) => widget.onCreateAfter(task, position),
            onPasteLines: widget.readOnlyTaskRefs
                ? null
                : (lines, position) =>
                      widget.onPasteAfter(task, lines, position),
            allTaskTitles: titles,
            autofocus: widget.focusTaskId == task.id,
            onAutofocused: widget.onFocusHandled,
            contextMenuFileType: widget.readOnlyTaskRefs
                ? null
                : widget.contextMenuFileType,
            contextMenuTargetBlock: widget.readOnlyTaskRefs
                ? null
                : widget.contextMenuTargetBlock,
            onBlockMenuAction: widget.readOnlyTaskRefs
                ? null
                : widget.onBlockMenuAction,
            onReadOnlyAction: widget.readOnlyTaskRefs
                ? widget.onReadOnlyAction
                : null,
            viewMenuContext: widget.viewMenuContext,
            readOnly: widget.readOnlyTaskRefs || task.isAutomationsTopic,
            toggleEnabled: true,
            onRowTap: task.hasAutomationFlow
                ? () => AutomationFlowRegistry.run(
                    context: context,
                    state: widget.state,
                    task: task,
                  )
                : null,
          ),
        if (!hideDraft)
          _DraftTaskRow(
            done: widget.done,
            hint: widget.state.strings['newTaskHint'],
            emojiSearchHint: widget.state.strings['searchEmoji'],
            emojiPickerTitle: widget.state.strings['insertEmoji'],
            aiState: widget.state,
            aiSuggestEmojiLabel: widget.state.strings['aiSuggestEmoji'],
            onSubmit: (title, position) =>
                widget.onCreateAtEnd(title, position),
          ),
      ],
    );
  }
}

class _DraftTaskRow extends StatefulWidget {
  const _DraftTaskRow({
    required this.done,
    required this.hint,
    required this.emojiSearchHint,
    required this.emojiPickerTitle,
    required this.aiState,
    required this.aiSuggestEmojiLabel,
    required this.onSubmit,
  });

  final bool done;
  final String hint;
  final String emojiSearchHint;
  final String emojiPickerTitle;
  final AppState aiState;
  final String aiSuggestEmojiLabel;
  final Future<void> Function(String title, Offset position) onSubmit;

  @override
  State<_DraftTaskRow> createState() => _DraftTaskRowState();
}

class _DraftTaskRowState extends State<_DraftTaskRow> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _controller.text;
    if (title.trim().isEmpty) return;
    final box = _focusNode.context?.findRenderObject() as RenderBox?;
    final position = box?.localToGlobal(Offset.zero) ?? Offset.zero;
    await widget.onSubmit(title, position);
    if (!mounted) return;
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final lineHeight = AppTypography.taskRowLineHeight;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 32, height: lineHeight),
          Expanded(
            child: FormattedTextField(
              controller: _controller,
              focusNode: _focusNode,
              textAlignVertical: TextAlignVertical.top,
              style: AppTypography.taskRowStyle.copyWith(
                decoration: widget.done ? TextDecoration.lineThrough : null,
                color: widget.done
                    ? Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.45)
                    : null,
              ),
              maxLines: null,
              minLines: 1,
              stripNewlines: true,
              hintText: widget.hint,
              emojiSearchHint: widget.emojiSearchHint,
              emojiPickerTitle: widget.emojiPickerTitle,
              aiState: widget.aiState,
              aiSuggestEmojiLabel: widget.aiSuggestEmojiLabel,
              onEnter: _submit,
            ),
          ),
        ],
      ),
    );
  }
}
