import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/models/app_file.dart';
import '../../core/models/block.dart';
import '../../core/models/task.dart';
import '../../shared/widgets/task_row.dart';

class TaskBlockWidget extends StatelessWidget {
  const TaskBlockWidget({
    super.key,
    required this.task,
    required this.state,
    required this.onToggle,
    required this.taskBlock,
    required this.file,
    required this.listBlock,
    this.allTaskTitles,
    this.onPasteLines,
  });

  final Task task;
  final AppState state;
  final VoidCallback onToggle;
  final Block taskBlock;
  final AppFile file;
  final Block listBlock;
  final List<String>? allTaskTitles;
  final Future<void> Function(List<String> lines)? onPasteLines;

  Block? _previousTaskBlock() {
    final blocks = state.selectedDetail?.blocksByFileId[file.id] ?? [];
    final index = blocks.indexWhere((b) => b.id == taskBlock.id);
    if (index <= 0) return null;
    for (var i = index - 1; i >= 0; i--) {
      if (blocks[i].type == 'task') return blocks[i];
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return TaskRow(
      task: task,
      state: state,
      onToggle: onToggle,
      taskBlock: taskBlock,
      allTaskTitles: allTaskTitles,
      onPasteLines: onPasteLines,
      autofocus: state.pendingFocusBlockId == taskBlock.id,
      onAutofocused: () => state.clearBlockFocus(taskBlock.id),
      onTitleChanged: (title) => state.updateTaskTitle(task, title),
      onDelete: () => state.deleteTaskWithBlock(
        task,
        taskBlock,
        focusTaskBlockAfterDelete: _previousTaskBlock(),
      ),
      onAddTaskAfter: () => state.insertTaskAfter(
        file: file,
        listBlock: listBlock,
        afterTaskBlock: taskBlock,
      ),
    );
  }
}
