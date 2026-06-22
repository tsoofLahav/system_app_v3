import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_state.dart';
import '../../core/models/app_file.dart';
import '../../core/models/block.dart';
import '../../core/models/task.dart';
import '../../design_system/app_typography.dart';
import '../../shared/widgets/task_assign_menu.dart';
import '../../shared/widgets/task_mark.dart';
import 'connected_lines_editor.dart';

/// Unified task list editor: one connected document synced to individual tasks.
class TasksConnectedEditor extends StatelessWidget {
  const TasksConnectedEditor({
    super.key,
    required this.file,
    required this.listBlock,
    required this.state,
  });

  final AppFile file;
  final Block listBlock;
  final AppState state;

  List<Task> get _orderedTasks => state.orderedTasksForFile(file, listBlock);

  @override
  Widget build(BuildContext context) {
    final ordered = _orderedTasks;
    final lines = ordered.map((task) => task.title).toList();
    if (lines.isEmpty) {
      lines.add('');
    }

    return ConnectedLinesEditor(
      lines: lines,
      style: AppTypography.taskRowStyle,
      hint: state.strings['newTaskHint'],
      lineAccessoryBuilder: (context, index) {
        if (index >= ordered.length) {
          return TaskMark(done: false, onToggle: () {});
        }
        final task = ordered[index];
        return TaskMark(
          done: task.isDone,
          onToggle: () => state.toggleTaskStatus(task),
        );
      },
      onLineSecondaryTap: (details, index) {
        if (index >= ordered.length) return;
        showTaskAssignMenu(
          context: context,
          globalPosition: details.globalPosition,
          task: ordered[index],
          state: state,
        );
      },
      onCopyAll: () {
        final titles = ordered.map((task) => task.title).toList();
        if (titles.isEmpty) return;
        Clipboard.setData(ClipboardData(text: titles.join('\n')));
      },
      onLinesChanged: (nextLines) {
        state.syncTasksFromLines(
          file: file,
          listBlock: listBlock,
          lines: nextLines,
        );
      },
    );
  }
}
