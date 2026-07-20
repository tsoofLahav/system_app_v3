import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/models/app_file.dart';
import '../../core/models/block.dart';
import '../../core/models/task.dart';
import '../../core/task_file_layout.dart';
import '../../design_system/app_typography.dart';
import '../blocks/block_context_menu.dart';
import 'task_drag_data.dart';
import 'task_lines_editor.dart';

/// Virtual task editor grouped by view assignment (flip mode).
class TasksFlipEditor extends StatefulWidget {
  const TasksFlipEditor({
    super.key,
    required this.file,
    required this.blocks,
    required this.state,
    this.onBlockMenuAction,
  });

  final AppFile file;
  final List<Block> blocks;
  final AppState state;
  final BlockMenuHandler? onBlockMenuAction;

  @override
  State<TasksFlipEditor> createState() => _TasksFlipEditorState();
}

class _TasksFlipEditorState extends State<TasksFlipEditor> {
  int? _focusTaskId;

  List<Task> _allTasks() {
    final entries = allTasksInFile(
      widget.blocks,
      widget.state.tasksByBlockIdForFile(widget.file),
    );
    return entries.map((entry) => entry.task).toList();
  }

  TaskZoneHandlers _handlers(Block listBlock) {
    return (
      onCreateAfter: (afterTask, _) async {
        final created = await widget.state.createTaskInFileAfter(
          file: widget.file,
          listBlock: listBlock,
          afterTask: afterTask,
        );
        if (created != null) {
          setState(() => _focusTaskId = created.id);
        }
      },
      onCreateAtEnd: (title, _) async {
        final listBlocks = widget.blocks
            .where((block) => block.type == 'task_list')
            .toList();
        final target = listBlocks.isNotEmpty ? listBlocks.first : listBlock;
        final created = await widget.state.createTaskInFileAfter(
          file: widget.file,
          listBlock: target,
          title: title,
        );
        if (created != null) {
          setState(() => _focusTaskId = created.id);
        }
      },
      onTitleChanged: (task, title) =>
          widget.state.updateTaskTitle(task, title),
      onDelete: (task) => widget.state.deleteTaskInFile(widget.file, task),
      onPasteAfter: (afterTask, lines, position) async {
        final listBlocks = widget.blocks
            .where((block) => block.type == 'task_list')
            .toList();
        final target = listBlocks.isNotEmpty ? listBlocks.first : listBlock;
        await widget.state.pasteTasksInFileAfter(
          file: widget.file,
          listBlock: target,
          afterTask: afterTask,
          lines: lines,
          status: afterTask.isDone ? 'done' : 'active',
        );
      },
    );
  }

  Block _fallbackListBlock() {
    return widget.blocks.firstWhere(
      (block) => block.type == 'task_list',
      orElse: () => widget.blocks.first,
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.state.strings;
    final groups = groupTasksByView(
      _allTasks(),
      widget.state.viewTypeForTask,
      unassignedLabel: strings['unassignedView'],
    );
    final fallbackListBlock = _fallbackListBlock();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final group in groups) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(
              group.label,
              style: AppTypography.blockHeaderStyle,
            ),
          ),
          _FlipViewDropZone(
            viewType: group.viewType,
            onAccept: (data) => widget.state.assignTaskView(
              data.task,
              group.viewType,
            ),
            child: TaskLinesEditor(
              tasks: group.tasks,
              state: widget.state,
              handlersFor: (_) => _handlers(fallbackListBlock),
              focusTaskId: _focusTaskId,
              onFocusHandled: () => setState(() => _focusTaskId = null),
              contextMenuFileType: widget.file.type,
              contextMenuTargetBlock: fallbackListBlock,
              onBlockMenuAction: widget.onBlockMenuAction,
              file: widget.file,
              enableReorder: false,
              enableCrossListDrag: true,
              flipViewType: group.viewType,
              listBlock: fallbackListBlock,
            ),
          ),
        ],
      ],
    );
  }
}

class _FlipViewDropZone extends StatelessWidget {
  const _FlipViewDropZone({
    required this.viewType,
    required this.onAccept,
    required this.child,
  });

  final String? viewType;
  final Future<void> Function(TaskDragData data) onAccept;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DragTarget<TaskDragData>(
      onWillAcceptWithDetails: (details) {
        final data = details.data;
        return data.flipViewType != viewType;
      },
      onAcceptWithDetails: (details) => onAccept(details.data),
      builder: (context, candidate, rejected) {
        final active = candidate.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: active
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)
                : null,
          ),
          child: child,
        );
      },
    );
  }
}
