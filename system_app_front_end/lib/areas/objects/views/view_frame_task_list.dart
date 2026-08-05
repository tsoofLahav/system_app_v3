import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../ui/confirm_dialog.dart';
import '../../ux/widgets/app_context_menu.dart';
import '../data/task.dart';
import '../tasks/task_list_surface.dart';
import './view_frame_options.dart';
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
    this.editableSection = false,
    this.onEditSection,
    this.onDeleteSection,
    this.homeLists = const [],
    this.sectionOptions = const [],
    this.topicOptions = const [],
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
  final bool editableSection;
  final Future<void> Function()? onEditSection;
  final Future<void> Function()? onDeleteSection;
  final List<ViewFrameListOption> homeLists;
  final List<ViewSectionOption> sectionOptions;
  final List<ViewTopicOption> topicOptions;
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
    if (oldWidget.reorderMode != widget.reorderMode) {
      _surfaceKey.currentState?.setReorderMode(widget.reorderMode);
    }
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

  Future<bool> _confirmLeaveHomeList({required bool forTopic}) async {
    if (!mounted) return false;
    final s = widget.state.strings;
    return showAppConfirmDialog(
      context: context,
      title: s['leaveHomeListTitle'],
      message: forTopic
          ? s['leaveHomeListForTopicBody']
          : s['leaveHomeListForListBody'],
      confirmLabel: s['leaveHomeListConfirm'],
      cancelLabel: s['cancel'],
      destructive: true,
    );
  }

  String? _sectionNameFor(Task task) {
    for (final m in widget.state.viewMemberships) {
      if (m.taskId == task.id) return m.sectionName;
    }
    return task.sectionName;
  }

  String _topicKeyFor(Task task) {
    for (final m in widget.state.viewMemberships) {
      if (m.taskId == task.id &&
          m.topicKey != null &&
          m.topicKey!.isNotEmpty) {
        return m.topicKey!;
      }
    }
    if (task.topicKey != null && task.topicKey!.isNotEmpty) {
      return task.topicKey!;
    }
    if (task.topicId != null) return 'topic_${task.topicId}';
    return 'no_topic';
  }

  int? _viewIdFor(Task task) {
    // In a view frame the selected view is current; still prefer membership.
    for (final m in widget.state.viewMemberships) {
      if (m.taskId == task.id) return m.viewId;
    }
    return widget.state.selectedView?.id;
  }

  List<AppContextMenuEntry> _extraEntries(Task task) {
    final s = widget.state.strings;
    final lists = widget.homeLists;
    final sections = widget.sectionOptions;
    final topics = widget.topicOptions;
    final views = widget.state.userViews;
    final currentSection = (_sectionNameFor(task) ?? '').trim();
    final currentTopic = _topicKeyFor(task);
    final currentListId = task.taskListId;
    final currentViewId = _viewIdFor(task);

    return [
      if (widget.editableSection) ...[
        const AppContextMenuDivider(),
        AppContextMenuItem(
          value: 'section_edit',
          label: s['editSection'],
        ),
        AppContextMenuItem(
          value: 'section_delete',
          label: s['deleteSection'],
          destructive: true,
        ),
      ],
      const AppContextMenuDivider(),
      // Origin-affecting: list + topic
      if (lists.isNotEmpty)
        AppContextMenuSubmenu(
          label: s['changeHomeList'],
          children: [
            for (final list in lists)
              AppContextMenuItem(
                value: 'list:${list.taskListId}',
                label: list.title.trim().isEmpty
                    ? s['untitledTaskList']
                    : list.title,
                checked: list.taskListId == currentListId,
              ),
          ],
        ),
      AppContextMenuSubmenu(
        label: s['changeTopic'],
        children: [
          for (final topic in topics)
            AppContextMenuItem(
              value: 'topic:${topic.key}',
              label: topic.label,
              checked: topic.key == currentTopic,
            ),
          AppContextMenuItem(
            value: 'topic:',
            label: s['noTopic'],
            checked: currentTopic == 'no_topic',
          ),
        ],
      ),
      const AppContextMenuDivider(),
      // View-only placement: section + view
      AppContextMenuSubmenu(
        label: s['changeSection'],
        children: [
          for (final section in sections)
            AppContextMenuItem(
              value: 'section:${section.name}',
              label: section.name,
              checked: section.name == currentSection,
            ),
          AppContextMenuItem(
            value: 'section:',
            label: s['uncategorized'],
            checked: currentSection.isEmpty,
          ),
        ],
      ),
      if (views.isNotEmpty)
        AppContextMenuSubmenu(
          label: s['assignTaskViews'],
          children: [
            for (final view in views)
              AppContextMenuItem(
                value: 'view:${view.id}',
                label: view.name,
                checked: view.id == currentViewId,
              ),
            AppContextMenuItem(
              value: 'view:',
              label: s['noView'],
              checked: currentViewId == null,
            ),
          ],
        ),
      AppContextMenuItem(
        value: 'delete',
        label: s['delete'],
        destructive: true,
      ),
    ];
  }

  Future<void> _onExtraAction(String action, Task task) async {
    if (action == 'section_edit') {
      await widget.onEditSection?.call();
      return;
    }
    if (action == 'section_delete') {
      await widget.onDeleteSection?.call();
      return;
    }
    if (action.startsWith('list:')) {
      final id = int.tryParse(action.substring('list:'.length));
      if (id == null) return;
      if (id == task.taskListId) return;
      if (task.taskListId != null) {
        final ok = await _confirmLeaveHomeList(forTopic: false);
        if (!ok) return;
      }
      await widget.state.assignViewTaskToList(task, id);
      await widget.state.refreshOpenTaskSurfaces(notify: true);
      return;
    }
    if (action.startsWith('topic:')) {
      final key = action.substring('topic:'.length);
      final nextKey = key.isEmpty ? 'no_topic' : key;
      if (nextKey == _topicKeyFor(task)) return;
      if (task.taskListId != null) {
        final ok = await _confirmLeaveHomeList(forTopic: true);
        if (!ok) return;
        await widget.state.clearTaskHomeList(task.id);
      }
      await widget.state.updateViewTaskPlacement(
        taskId: task.id,
        topicKey: key.isEmpty ? null : key,
        clearTopic: key.isEmpty,
      );
      return;
    }
    if (action.startsWith('section:')) {
      final name = action.substring('section:'.length);
      final sections = widget.sectionOptions;
      final match = name.isEmpty
          ? null
          : sections.where((o) => o.name == name).firstOrNull;
      await widget.state.updateViewTaskPlacement(
        taskId: task.id,
        sectionName: match?.name,
        sectionFlag: match?.flag,
        clearSection: name.isEmpty,
      );
      return;
    }
    if (action.startsWith('view:')) {
      final raw = action.substring('view:'.length);
      final viewId = raw.isEmpty ? null : int.tryParse(raw);
      if (raw.isNotEmpty && viewId == null) return;
      await widget.state.setTaskView(task.id, viewId);
      await widget.state.refreshOpenTaskSurfaces(notify: true);
    }
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

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    if (!it.moveNext()) return null;
    return it.current;
  }
}
