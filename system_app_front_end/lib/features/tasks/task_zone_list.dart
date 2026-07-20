import 'package:flutter/material.dart';

import '../../core/models/app_file.dart';
import '../../core/app_state.dart';
import '../../core/ai/ai_context.dart';
import '../../core/models/block.dart';
import '../../core/models/task.dart';
import '../../core/models/task_view_menu_context.dart';
import '../../design_system/app_icons.dart';
import '../../design_system/app_typography.dart';
import '../../features/blocks/formatted_text_field.dart';
import '../../core/registry/automation_flow_registry.dart';
import '../../features/shell/automation_abandon_dialog.dart';
import '../../shared/widgets/task_row.dart';
import '../blocks/block_context_menu.dart';
import 'task_drag_data.dart';

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
    this.listBlock,
    this.enableReorder = false,
    this.enableCrossListDrag = false,
    this.flipViewType,
    this.flipGroupTasks,
    this.listBlockByTaskId,
  });

  final List<Task> tasks;
  final bool done;
  final AppState state;
  final AppFile? file;
  final Block? listBlock;
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
  final bool enableReorder;
  final bool enableCrossListDrag;
  final String? flipViewType;
  final List<Task>? flipGroupTasks;
  final Map<int, Block>? listBlockByTaskId;

  @override
  State<TaskZoneList> createState() => _TaskZoneListState();
}

class _TaskZoneListState extends State<TaskZoneList> {
  bool get _canMutate =>
      !widget.readOnlyTaskRefs && widget.file != null && widget.listBlock != null;

  bool get _showGrip =>
      _canMutate &&
      ((widget.enableReorder && widget.tasks.length > 1) ||
          widget.enableCrossListDrag);

  bool get _showDropTargets =>
      _canMutate &&
      ((widget.enableReorder && widget.tasks.length > 1) ||
          widget.enableCrossListDrag);

  bool _isSameZone(TaskDragPayload payload) {
    return payload.sourceListBlock.id == widget.listBlock?.id &&
        payload.sourceDone == widget.done &&
        payload.sourceViewType == widget.flipViewType;
  }

  bool _willAcceptDrop(TaskDragPayload payload, int targetIndex) {
    if (!_showDropTargets) return false;
    final fromIndex = widget.tasks.indexWhere((t) => t.id == payload.task.id);
    if (_isSameZone(payload)) {
      if (fromIndex < 0) return false;
      if (fromIndex == targetIndex) return false;
      return true;
    }
    if (payload.sourceListBlock.id == widget.listBlock?.id &&
        payload.sourceViewType == widget.flipViewType) {
      return widget.enableReorder;
    }
    return widget.enableCrossListDrag;
  }

  Widget _dragHandle() {
    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(top: 2, end: 4),
        child: SizedBox(
          width: 20,
          height: AppTypography.taskRowLineHeight,
          child: Center(
            child: AppIcon(
              AppIcons.drag,
              size: 16,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.35),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTaskRow(Task task, List<String> titles) {
    return TaskRow(
      key: ValueKey(task.id),
      task: task,
      state: widget.state,
      taskBlock: widget.file != null
          ? widget.state.taskRowBlockInFile(widget.file!, task)
          : null,
      onToggle: () => widget.state.toggleTaskStatus(
        task,
        confirmAbandonCompanionFlow: () => showAutomationAbandonChangesDialog(
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
          : (lines, position) => widget.onPasteAfter(task, lines, position),
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
      aiFileId: widget.file?.id,
    );
  }

  Future<void> _handleDrop(TaskDragPayload payload, int targetIndex) async {
    final file = widget.file;
    final listBlock = widget.listBlock;
    if (file == null || listBlock == null) return;

    final sourceIndex = _isSameZone(payload)
        ? widget.tasks.indexWhere((t) => t.id == payload.task.id)
        : -1;

    await widget.state.applyTaskDrop(
      file: file,
      payload: payload,
      targetListBlock: listBlock,
      targetViewType: widget.flipViewType,
      targetDone: widget.done,
      insertIndex: targetIndex,
      sourceIndexInZone: sourceIndex,
      targetZoneLength: widget.tasks.length,
      isFlipMode: widget.flipViewType != null,
      allowCrossBoundary: widget.enableCrossListDrag,
      listBlockByTaskId: widget.listBlockByTaskId,
      flipGroupTasks: widget.flipGroupTasks,
    );
  }

  Widget _buildDragHandle(Task task) {
    final payload = TaskDragPayload(
      task: task,
      sourceListBlock: widget.listBlock!,
      sourceDone: widget.done,
      sourceViewType: widget.flipViewType,
    );

    return Draggable<TaskDragPayload>(
      data: payload,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        elevation: 4,
        color: Theme.of(context).colorScheme.surface,
        child: SizedBox(
          width: 280,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _dragHandle(),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    task.title,
                    style: AppTypography.taskRowStyle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.25, child: _dragHandle()),
      child: _dragHandle(),
    );
  }

  Widget _buildListItem(Task task, List<String> titles, int index) {
    Widget rowContent = _buildTaskRow(task, titles);

    if (_showDropTargets) {
      rowContent = DragTarget<TaskDragPayload>(
        onWillAcceptWithDetails: (details) =>
            _willAcceptDrop(details.data, index),
        onAcceptWithDetails: (details) => _handleDrop(details.data, index),
        builder: (context, candidate, rejected) {
          final active = candidate.isNotEmpty;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              border: active
                  ? Border(
                      top: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2,
                      ),
                    )
                  : null,
            ),
            child: rowContent,
          );
        },
      );
    }

    if (!_showGrip) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_showDropTargets) SizedBox(width: 20, child: _dragHandle()),
          Expanded(child: rowContent),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDragHandle(task),
        Expanded(child: rowContent),
      ],
    );
  }

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
        for (var i = 0; i < widget.tasks.length; i++)
          _buildListItem(widget.tasks[i], titles, i),
        if (_showDropTargets)
          DragTarget<TaskDragPayload>(
            onWillAcceptWithDetails: (details) =>
                _willAcceptDrop(details.data, widget.tasks.length),
            onAcceptWithDetails: (details) =>
                _handleDrop(details.data, widget.tasks.length),
            builder: (context, candidate, rejected) {
              return SizedBox(
                height: candidate.isNotEmpty ? 8 : 0,
              );
            },
          ),
        if (!hideDraft)
          _DraftTaskRow(
            done: widget.done,
            hint: widget.state.strings['newTaskHint'],
            emojiSearchHint: widget.state.strings['searchEmoji'],
            emojiPickerTitle: widget.state.strings['insertEmoji'],
            aiFileId: widget.file?.id,
            state: widget.state,
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
    required this.aiFileId,
    required this.state,
    required this.onSubmit,
  });

  final bool done;
  final String hint;
  final String emojiSearchHint;
  final String emojiPickerTitle;
  final int? aiFileId;
  final AppState state;
  final Future<void> Function(String title, Offset position) onSubmit;

  @override
  State<_DraftTaskRow> createState() => _DraftTaskRowState();
}

class _DraftTaskRowState extends State<_DraftTaskRow> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_reportAiFocus);
    _focusNode.addListener(_reportAiFocus);
  }

  @override
  void dispose() {
    _controller.removeListener(_reportAiFocus);
    _focusNode.removeListener(_reportAiFocus);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _reportAiFocus() {
    if (!_focusNode.hasFocus) return;
    final fileId = widget.aiFileId;
    if (fileId == null) return;
    widget.state.setAiFocus(
      AiFocus(
        fileId: fileId,
        fullText: _controller.text,
        selection: _controller.selection,
        isTaskInput: true,
      ),
    );
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
              onChanged: (_) => _reportAiFocus(),
              onEnter: _submit,
            ),
          ),
        ],
      ),
    );
  }
}
