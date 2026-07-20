import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/models/app_file.dart';
import '../../core/models/block.dart';
import '../../core/models/task.dart';
import '../../core/task_file_layout.dart';
import '../../core/task_list_order.dart';
import '../../design_system/app_typography.dart';
import '../blocks/block_context_menu.dart';
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
    return allTasksInFile(
      widget.blocks,
      widget.state.tasksByBlockIdForFile(widget.file),
    ).map((entry) => entry.task).toList();
  }

  TaskZoneHandlers _handlers(
    Block fallbackListBlock,
    Map<int, Block> listBlockByTaskId, {
    required String? viewType,
    required bool done,
  }) {
    final status = done ? 'done' : 'active';
    return (
      onCreateAfter: (afterTask, _) async {
        final targetList = afterTask != null
            ? (listBlockByTaskId[afterTask.id] ?? fallbackListBlock)
            : fallbackListBlock;
        final created = await widget.state.createTaskInFileAfter(
          file: widget.file,
          listBlock: targetList,
          afterTask: afterTask,
          status: status,
          flipViewType: viewType,
        );
        if (created != null) {
          setState(() => _focusTaskId = created.id);
        }
      },
      onCreateAtEnd: (title, _) async {
        final listBlocks = widget.blocks
            .where((block) => block.type == 'task_list')
            .toList();
        final target = listBlocks.isNotEmpty ? listBlocks.first : fallbackListBlock;
        final parts = partitionTasks(
          viewType == null
              ? widget.state.orderedTasksForFile(widget.file, target)
              : _allTasks()
                  .where(
                    (task) =>
                        widget.state.viewTypeForTask(task.id) == viewType,
                  )
                  .toList(),
        );
        final zone = done ? parts.done : parts.active;
        final created = await widget.state.createTaskInFileAfter(
          file: widget.file,
          listBlock: target,
          afterTask: zone.isEmpty ? null : zone.last,
          title: title,
          status: status,
          flipViewType: viewType,
        );
        if (created != null) {
          setState(() => _focusTaskId = created.id);
        }
      },
      onTitleChanged: (task, title) =>
          widget.state.updateTaskTitle(task, title),
      onDelete: (task) => widget.state.deleteTaskInFile(widget.file, task),
      onPasteAfter: (afterTask, lines, position) async {
        final target = listBlockByTaskId[afterTask.id] ?? fallbackListBlock;
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
    final taskEntries = allTasksInFile(
      widget.blocks,
      widget.state.tasksByBlockIdForFile(widget.file),
    );
    final listBlockByTaskId = {
      for (final entry in taskEntries) entry.task.id: entry.listBlock,
    };
    final listBlocks = sortedBlocksForFile(widget.blocks)
        .where((block) => block.type == 'task_list')
        .toList();
    final listBlockOrderIndex = {
      for (var i = 0; i < listBlocks.length; i++) listBlocks[i].id: i,
    };
    final taskById = {for (final entry in taskEntries) entry.task.id: entry.task};
    int listOrderForTask(int taskId) {
      final task = taskById[taskId];
      if (task == null) return 0;
      final listIndex = listBlockOrderIndex[task.blockId] ?? 0;
      return listIndex * 100000 + task.listOrderIndex;
    }
    final groups = groupTasksByView(
      _allTasks(),
      widget.state.viewTypeForTask,
      membershipOrderForTask: widget.state.orderIndexForTask,
      blockOrderForTask: listOrderForTask,
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
          TaskLinesEditor(
            tasks: group.tasks,
            state: widget.state,
            handlersFor: (done) => _handlers(
              fallbackListBlock,
              listBlockByTaskId,
              viewType: group.viewType,
              done: done,
            ),
            focusTaskId: _focusTaskId,
            onFocusHandled: () => setState(() => _focusTaskId = null),
            contextMenuFileType: widget.file.type,
            contextMenuTargetBlock: fallbackListBlock,
            onBlockMenuAction: widget.onBlockMenuAction,
            file: widget.file,
            listBlock: fallbackListBlock,
            enableReorder: true,
            enableCrossListDrag: true,
            flipViewType: group.viewType,
            flipGroupTasks: group.tasks,
            listBlockByTaskId: listBlockByTaskId,
          ),
        ],
      ],
    );
  }
}
