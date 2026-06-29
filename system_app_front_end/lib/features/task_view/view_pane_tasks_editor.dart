import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/models/task.dart';
import '../../core/models/task_view_menu_context.dart';
import '../../core/models/view_pane_sync_context.dart';
import '../../core/registry/task_view_display.dart';
import '../../core/task_list_order.dart';
import '../../shared/widgets/task_context_menu.dart';
import '../tasks/task_lines_editor.dart';

/// Per-task editors for a view pane column (active + done zones).
class ViewPaneTasksEditor extends StatefulWidget {
  const ViewPaneTasksEditor({
    super.key,
    required this.viewType,
    required this.displayMode,
    required this.tasks,
    required this.state,
    this.sectionName,
    this.topicKey,
  });

  final String viewType;
  final TaskViewDisplayMode displayMode;
  final String? sectionName;
  final String? topicKey;
  final List<Task> tasks;
  final AppState state;

  @override
  State<ViewPaneTasksEditor> createState() => _ViewPaneTasksEditorState();
}

class _ViewPaneTasksEditorState extends State<ViewPaneTasksEditor> {
  final _editorKey = GlobalKey();
  int? _focusTaskId;

  ViewPaneSyncContext get _syncContext => ViewPaneSyncContext(
        viewType: widget.viewType,
        displayMode: widget.displayMode,
        sectionName: widget.sectionName,
        topicKey: widget.topicKey,
      );

  TaskViewMenuContext get _menuContext => TaskViewMenuContext(
        viewType: widget.viewType,
        displayMode: widget.displayMode,
        sectionName: widget.sectionName,
      );

  TaskZoneHandlers _handlers(bool done) {
    return (
      onCreateAfter: (afterTask, position) async {
        final created = await widget.state.createTaskInViewZoneAfter(
          pane: _syncContext,
          afterTask: afterTask,
          done: done,
          pickTopic: (pos) => showViewTopicPickerMenu(
            context: context,
            globalPosition: pos,
            state: widget.state,
          ),
          menuPosition: position,
        );
        if (created != null) {
          setState(() => _focusTaskId = created.id);
        }
      },
      onCreateAtEnd: (title, position) async {
        final parts = partitionTasksById(widget.tasks);
        final zone = done ? parts.done : parts.active;
        final created = await widget.state.createTaskInViewZoneAfter(
          pane: _syncContext,
          afterTask: zone.isEmpty ? null : zone.last,
          title: title,
          done: done,
          pickTopic: (pos) => showViewTopicPickerMenu(
            context: context,
            globalPosition: pos,
            state: widget.state,
          ),
          menuPosition: position,
        );
        if (created != null) {
          setState(() => _focusTaskId = created.id);
        }
      },
      onTitleChanged: (task, title) =>
          widget.state.updateTaskTitle(task, title),
      onDelete: (task) => widget.state.deleteTaskInView(task),
      onPasteAfter: (afterTask, lines, position) =>
          widget.state.pasteTasksInViewAfter(
            pane: _syncContext,
            afterTask: afterTask,
            lines: lines,
            done: done,
            pickTopic: (pos) => showViewTopicPickerMenu(
              context: context,
              globalPosition: pos,
              state: widget.state,
            ),
            menuPosition: position,
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: _editorKey,
      child: TaskLinesEditor(
        tasks: sortTasksById(widget.tasks),
        state: widget.state,
        viewMenuContext: _menuContext,
        focusTaskId: _focusTaskId,
        onFocusHandled: () => setState(() => _focusTaskId = null),
        handlersFor: _handlers,
      ),
    );
  }
}
