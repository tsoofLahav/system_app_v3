import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../ui/confirm_dialog.dart';
import '../../ux/widgets/app_context_menu.dart';
import '../data/task.dart';
import '../tasks/task_list_surface.dart';
import './assign_task_view_dialog.dart';
import './place_task_dialog.dart';
import './view_frame_task_list_bridge.dart';

/// One view frame's task list — [TaskListSurface] + view placement menus.
class ViewFrameTaskList extends StatefulWidget {
  const ViewFrameTaskList({
    super.key,
    required this.state,
    required this.tasks,
    this.sectionName,
    this.sectionFlag,
    this.topicKey,
    this.reorderMode = false,
    this.onReorderModeChanged,
    this.onForeignDrop,
    this.enabled = true,
  });

  final AppState state;
  final List<Task> tasks;
  final String? sectionName;
  final String? sectionFlag;
  final String? topicKey;
  final bool reorderMode;
  final ValueChanged<bool>? onReorderModeChanged;
  final TaskListForeignDrop? onForeignDrop;
  final bool enabled;

  @override
  State<ViewFrameTaskList> createState() => _ViewFrameTaskListState();
}

class _ViewFrameTaskListState extends State<ViewFrameTaskList> {
  late ViewFrameTaskListBridge _bridge;
  final _surfaceKey = GlobalKey<TaskListSurfaceState>();

  @override
  void initState() {
    super.initState();
    _bridge = _makeBridge();
  }

  @override
  void didUpdateWidget(ViewFrameTaskList oldWidget) {
    super.didUpdateWidget(oldWidget);
    _bridge.frameTasks = widget.tasks;
    _bridge.sectionName = widget.sectionName;
    _bridge.sectionFlag = widget.sectionFlag;
    _bridge.topicKey = widget.topicKey;
    final tasksArrived =
        widget.tasks.isNotEmpty &&
        (oldWidget.tasks.length != widget.tasks.length ||
            !_sameTaskIds(oldWidget.tasks, widget.tasks));
    if (tasksArrived) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _surfaceKey.currentState?.syncFromRemote();
      });
    }
    if (oldWidget.reorderMode != widget.reorderMode) {
      _surfaceKey.currentState?.setReorderMode(widget.reorderMode);
    }
  }

  bool _sameTaskIds(List<Task> a, List<Task> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  ViewFrameTaskListBridge _makeBridge() {
    return ViewFrameTaskListBridge(
      state: widget.state,
      frameTasks: widget.tasks,
      sectionName: widget.sectionName,
      sectionFlag: widget.sectionFlag,
      topicKey: widget.topicKey,
      confirmDeleteFn: _confirmDelete,
    );
  }

  Future<bool> _confirmDelete(Task task) async {
    if (task.taskListId == null) return true;
    if (!mounted) return false;
    final s = widget.state.strings;
    return showAppConfirmDialog(
      context: context,
      title: s['deleteTaskTitle'],
      message: s['deleteTaskFromViewBody'],
      confirmLabel: s['delete'],
      cancelLabel: s['cancel'],
      destructive: true,
    );
  }

  List<AppContextMenuEntry> _extraEntries(Task task) {
    final s = widget.state.strings;
    return [
      const AppContextMenuDivider(),
      AppContextMenuItem(value: 'view_section', label: s['assignTaskViews']),
      AppContextMenuItem(value: 'topic_list', label: s['placeTopicList']),
      AppContextMenuItem(
        value: 'delete',
        label: s['delete'],
        destructive: true,
      ),
    ];
  }

  Future<void> _onExtraAction(String action, Task task) async {
    if (action != 'view_section' && action != 'topic_list') return;
    if (!mounted) return;
    final marked = _surfaceKey.currentState?.markedTaskIds() ?? const <int>[];
    final byId = {for (final t in widget.tasks) t.id: t};
    final targets = <Task>[
      for (final id in marked)
        if (byId[id] != null) byId[id]!,
    ];
    if (targets.isEmpty) targets.add(task);
    if (action == 'view_section') {
      await showAssignTaskViewDialog(
        context: context,
        state: widget.state,
        taskIds: [for (final t in targets) t.id],
      );
      return;
    }
    await showPlaceTaskTopicListDialog(
      context: context,
      state: widget.state,
      tasks: targets,
    );
  }

  @override
  Widget build(BuildContext context) {
    _bridge.frameTasks = widget.tasks;

    return IgnorePointer(
      ignoring: !widget.enabled,
      child: TaskListSurface(
        key: _surfaceKey,
        state: widget.state,
        bridge: _bridge,
        onExitBelow: (_) {
          FocusManager.instance.primaryFocus?.unfocus();
        },
        climbToListTitleOnLastBackspace: false,
        includeAssignView: false,
        extraMenuEntries: _extraEntries,
        onExtraMenuAction: _onExtraAction,
        onForeignDrop: widget.onForeignDrop,
        onReorderModeChanged: widget.onReorderModeChanged,
      ),
    );
  }
}
