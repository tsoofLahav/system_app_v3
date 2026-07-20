import 'package:flutter/material.dart';

import '../../core/models/app_file.dart';
import '../../core/app_state.dart';
import '../../core/models/block.dart';
import '../../core/models/task.dart';
import '../../core/models/task_view_menu_context.dart';
import '../../core/task_list_order.dart';
import '../blocks/block_context_menu.dart';
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
    this.onBlockMenuAction,
    this.readOnlyTaskRefs = false,
    this.onReadOnlyAction,
    this.viewMenuContext,
    this.file,
    this.listBlock,
    this.enableReorder = false,
    this.enableCrossListDrag = false,
    this.flipViewType,
  });

  final List<Task> tasks;
  final AppState state;
  final TaskZoneHandlers Function(bool done) handlersFor;
  final int? focusTaskId;
  final VoidCallback? onFocusHandled;
  final String? contextMenuFileType;
  final Block? contextMenuTargetBlock;
  final BlockMenuHandler? onBlockMenuAction;
  final bool readOnlyTaskRefs;
  final VoidCallback? onReadOnlyAction;
  final TaskViewMenuContext? viewMenuContext;
  final AppFile? file;
  final Block? listBlock;
  final bool enableReorder;
  final bool enableCrossListDrag;
  final String? flipViewType;

  @override
  Widget build(BuildContext context) {
    final parts = partitionTasks(tasks);
    final showDone = parts.done.isNotEmpty;
    final canMutate = !readOnlyTaskRefs && file != null && listBlock != null;

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
          onBlockMenuAction: onBlockMenuAction,
          readOnlyTaskRefs: readOnlyTaskRefs,
          onReadOnlyAction: onReadOnlyAction,
          viewMenuContext: viewMenuContext,
          file: file,
          listBlock: listBlock,
          enableReorder: enableReorder && canMutate,
          enableCrossListDrag: enableCrossListDrag && canMutate,
          flipViewType: flipViewType,
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
            onBlockMenuAction: onBlockMenuAction,
            readOnlyTaskRefs: readOnlyTaskRefs,
            onReadOnlyAction: onReadOnlyAction,
            viewMenuContext: viewMenuContext,
            file: file,
            listBlock: listBlock,
            enableReorder: enableReorder && canMutate,
            enableCrossListDrag: enableCrossListDrag && canMutate,
            flipViewType: flipViewType,
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
