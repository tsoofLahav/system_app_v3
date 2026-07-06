import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/models/app_file.dart';
import '../../core/models/block.dart';
import '../../core/task_list_order.dart';
import '../tasks/task_lines_editor.dart';
import 'block_context_menu.dart';

/// Per-task editors for a topic tasks file (active + done zones).
class TasksConnectedEditor extends StatefulWidget {
  const TasksConnectedEditor({
    super.key,
    required this.file,
    required this.listBlock,
    required this.state,
    this.onBlockMenuAction,
  });

  final AppFile file;
  final Block listBlock;
  final AppState state;
  final BlockMenuHandler? onBlockMenuAction;

  @override
  State<TasksConnectedEditor> createState() => _TasksConnectedEditorState();
}

class _TasksConnectedEditorState extends State<TasksConnectedEditor> {
  int? _focusTaskId;

  bool get _isGeneratedProjectSummaryList =>
      widget.listBlock.content['generated_by'] == 'project_summary_update';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncFocusFromPendingBlock();
  }

  @override
  void didUpdateWidget(TasksConnectedEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncFocusFromPendingBlock();
  }

  void _syncFocusFromPendingBlock() {
    final blockId = widget.state.pendingFocusBlockId;
    if (blockId == null) return;
    for (final block
        in widget.state.selectedDetail?.blocksByFileId[widget.file.id] ?? []) {
      if (block.id == blockId && block.type == 'task') {
        setState(() {
          _focusTaskId = block.content['task_id'] as int?;
        });
        return;
      }
    }
  }

  TaskZoneHandlers _handlers(bool done) {
    final status = done ? 'done' : 'active';
    return (
      onCreateAfter: (afterTask, _) async {
        final created = await widget.state.createTaskInFileAfter(
          file: widget.file,
          listBlock: widget.listBlock,
          afterTask: afterTask,
          status: status,
        );
        if (created != null) {
          setState(() => _focusTaskId = created.id);
        }
      },
      onCreateAtEnd: (title, _) async {
        final parts = partitionTasksById(
          widget.state.orderedTasksForFile(widget.file, widget.listBlock),
        );
        final zone = done ? parts.done : parts.active;
        final created = await widget.state.createTaskInFileAfter(
          file: widget.file,
          listBlock: widget.listBlock,
          afterTask: zone.isEmpty ? null : zone.last,
          title: title,
          status: status,
        );
        if (created != null) {
          setState(() => _focusTaskId = created.id);
        }
      },
      onTitleChanged: (task, title) =>
          widget.state.updateTaskTitle(task, title),
      onDelete: (task) => widget.state.deleteTaskInFile(widget.file, task),
      onPasteAfter: (afterTask, lines, position) =>
          widget.state.pasteTasksInFileAfter(
            file: widget.file,
            listBlock: widget.listBlock,
            afterTask: afterTask,
            lines: lines,
            status: status,
          ),
    );
  }

  void _showReadOnlyReferenceMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(widget.state.strings['summaryTasksReadOnly'])),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tasks = widget.state.orderedTasksForFile(
      widget.file,
      widget.listBlock,
    );

    return TaskLinesEditor(
      tasks: tasks,
      state: widget.state,
      focusTaskId: _focusTaskId,
      onFocusHandled: () {
        final blockId = widget.state.pendingFocusBlockId;
        if (blockId != null) widget.state.clearBlockFocus(blockId);
        setState(() => _focusTaskId = null);
      },
      contextMenuFileType: widget.file.type,
      contextMenuTargetBlock: widget.listBlock,
      onBlockMenuAction: _isGeneratedProjectSummaryList
          ? null
          : widget.onBlockMenuAction,
      readOnlyTaskRefs: _isGeneratedProjectSummaryList,
      onReadOnlyAction: _showReadOnlyReferenceMessage,
      file: widget.file,
      handlersFor: _handlers,
    );
  }
}
