import 'package:flutter/material.dart';

import '../../core/models/app_file.dart';
import '../../core/app_state.dart';
import '../../core/models/block.dart';
import '../../core/models/task.dart';
import '../../core/models/task_view_menu_context.dart';
import '../../core/task_list_order.dart';
import 'task_zone_list.dart';

typedef TaskZoneHandlers = ({
  Future<void> Function(Task? afterTask, Offset position) onCreateAfter,
  Future<void> Function(String title, Offset position) onCreateAtEnd,
  Future<void> Function(Task task, String title) onTitleChanged,
  Future<void> Function(Task task) onDelete,
  Future<void> Function(Task afterTask, List<String> lines, Offset position)
      onPasteAfter,
});

/// Active and done zones as separate per-task lists.
class TaskLinesEditor extends StatelessWidget {
  const TaskLinesEditor({
    super.key,
    required this.tasks,
    required this.state,
    required this.handlersFor,
    this.focusTaskId,
    this.onFocusHandled,
    this.contextMenuFileType,
    this.contextMenuTargetBlock,
    this.viewMenuContext,
    this.file,
  });

  final List<Task> tasks;
  final AppState state;
  final TaskZoneHandlers Function(bool done) handlersFor;
  final int? focusTaskId;
  final VoidCallback? onFocusHandled;
  final String? contextMenuFileType;
  final Block? contextMenuTargetBlock;
  final TaskViewMenuContext? viewMenuContext;
  final AppFile? file;

  @override
  Widget build(BuildContext context) {
    final parts = partitionTasksById(tasks);
    final showDone = parts.done.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TaskZoneList(
          tasks: parts.active,
          done: false,
          state: state,
          focusTaskId: focusTaskId,
          onFocusHandled: onFocusHandled,
          contextMenuFileType: contextMenuFileType,
          contextMenuTargetBlock: contextMenuTargetBlock,
          viewMenuContext: viewMenuContext,
          file: file,
          onCreateAfter: handlersFor(false).onCreateAfter,
          onCreateAtEnd: handlersFor(false).onCreateAtEnd,
          onTitleChanged: handlersFor(false).onTitleChanged,
          onDelete: handlersFor(false).onDelete,
          onPasteAfter: handlersFor(false).onPasteAfter,
        ),
        if (showDone) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Divider(
              height: 1,
              thickness: 1,
              color: Theme.of(context).dividerColor.withValues(alpha: 0.35),
            ),
          ),
          TaskZoneList(
            tasks: parts.done,
            done: true,
            state: state,
            focusTaskId: focusTaskId,
            onFocusHandled: onFocusHandled,
            contextMenuFileType: contextMenuFileType,
            contextMenuTargetBlock: contextMenuTargetBlock,
            viewMenuContext: viewMenuContext,
            file: file,
            onCreateAfter: handlersFor(true).onCreateAfter,
            onCreateAtEnd: handlersFor(true).onCreateAtEnd,
            onTitleChanged: handlersFor(true).onTitleChanged,
            onDelete: handlersFor(true).onDelete,
            onPasteAfter: handlersFor(true).onPasteAfter,
          ),
        ],
      ],
    );
  }
}
