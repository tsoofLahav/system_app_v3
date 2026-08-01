import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../ui/adaptive_dialog.dart';
import '../../ui/app_colors.dart';
import '../../ui/app_icons.dart';
import '../../ui/app_typography.dart';
import '../../ui/dialog_field_style.dart';
import '../data/task.dart';
import '../tasks/task_drag_data.dart';
import '../tasks/task_row.dart';
import '../tasks/task_zones.dart';

class TaskViewPane extends StatefulWidget {
  const TaskViewPane({super.key, required this.state});

  final AppState state;

  @override
  State<TaskViewPane> createState() => _TaskViewPaneState();
}

class _TaskViewPaneState extends State<TaskViewPane> {
  List<Task>? _optimisticTasks;
  var _persisting = false;

  AppState get state => widget.state;

  List<Task> get _remoteTasks {
    final withOrder = <({Task task, int order})>[];
    for (final m in state.viewMemberships) {
      if (m.task == null) continue;
      withOrder.add((task: Task.fromJson(m.task!), order: m.orderIndex));
    }
    withOrder.sort((a, b) => a.order.compareTo(b.order));
    return TaskZones.fromOrdered([for (final e in withOrder) e.task]).all;
  }

  List<Task> get _displayTasks => _optimisticTasks ?? _remoteTasks;

  @override
  void didUpdateWidget(TaskViewPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_persisting) return;
    if (_optimisticTasks != null &&
        _idsMatch(_optimisticTasks!, _remoteTasks)) {
      setState(() => _optimisticTasks = null);
    }
  }

  bool _idsMatch(List<Task> a, List<Task> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].isDone != b[i].isDone) return false;
    }
    return true;
  }

  List<Map<String, dynamic>> _membershipPayload(List<Task> ordered) {
    final byTaskId = {
      for (final m in state.viewMemberships)
        if (m.taskId != null) m.taskId!: m,
    };
    final placeholders = [
      for (final m in state.viewMemberships)
        if (m.taskId == null) m,
    ];
    final out = <Map<String, dynamic>>[];
    var index = 0;
    for (final t in ordered) {
      final existing = byTaskId[t.id];
      out.add({
        'task_id': t.id,
        'section_name': existing?.sectionName,
        'order_index': index++,
        'section_flag': existing?.sectionFlag,
        'topic_key': existing?.topicKey,
      });
    }
    for (final m in placeholders) {
      out.add({
        'task_id': null,
        'section_name': m.sectionName,
        'order_index': index++,
        'section_flag': m.sectionFlag,
        'topic_key': m.topicKey,
      });
    }
    return out;
  }

  Future<void> _persistZones(TaskZones next, TaskZones snapshot) async {
    _persisting = true;
    try {
      final before = {for (final t in snapshot.all) t.id: t};
      for (final t in next.all) {
        final was = before[t.id];
        if (was != null && was.isDone != t.isDone) {
          await state.toggleTaskStatus(was, notify: false);
        }
      }
      await state.reorderViewMemberships(
        _membershipPayload(next.all),
        notify: false,
      );
      await state.refreshOpenTaskSurfaces(notify: true);
      if (mounted) {
        setState(() => _optimisticTasks = null);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _optimisticTasks = snapshot.all);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(state.strings['reorderFailed']),
        ),
      );
    } finally {
      _persisting = false;
    }
  }

  void _onDrop({
    required Task task,
    required bool sourceDone,
    required bool targetDone,
    required int indexInZone,
  }) {
    final zones = TaskZones.fromOrdered(_displayTasks);
    final next = zones.moved(
      taskId: task.id,
      targetDone: targetDone,
      indexInZone: indexInZone,
    );
    if (next.orderedIds.join() == zones.orderedIds.join() &&
        sourceDone == targetDone) {
      return;
    }
    setState(() => _optimisticTasks = next.all);
    unawaited(_persistZones(next, zones));
  }

  Future<void> _toggle(Task task) async {
    final zones = TaskZones.fromOrdered(_displayTasks);
    final targetDone = !task.isDone;
    final next = zones.moved(
      taskId: task.id,
      targetDone: targetDone,
      indexInZone: targetDone ? zones.done.length : zones.active.length,
    );
    setState(() => _optimisticTasks = next.all);
    unawaited(_persistZones(next, zones));
  }

  Widget _zoneLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Text(
        text,
        style: AppTypography.metaStyle.copyWith(
          color: AppColors.textHint,
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _dropGap({required bool targetDone, required int indexInZone}) {
    return DragTarget<TaskDragPayload>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (d) => _onDrop(
        task: d.data.task,
        sourceDone: d.data.sourceDone,
        targetDone: targetDone,
        indexInZone: indexInZone,
      ),
      builder: (context, candidate, rejected) {
        final hot = candidate.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          height: hot ? 12 : 4,
          decoration: BoxDecoration(
            color: hot
                ? AppColors.primary.withValues(alpha: 0.35)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      },
    );
  }

  Widget _taskTile(Task task) {
    final zones = TaskZones.fromOrdered(_displayTasks);
    final inDone = task.isDone;
    final zone = inDone ? zones.done : zones.active;
    final zoneIndex = zone.indexWhere((t) => t.id == task.id);

    return DragTarget<TaskDragPayload>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (d) => _onDrop(
        task: d.data.task,
        sourceDone: d.data.sourceDone,
        targetDone: inDone,
        indexInZone: zoneIndex < 0 ? zone.length : zoneIndex,
      ),
      builder: (context, candidate, rejected) {
        return Column(
          children: [
            if (candidate.isNotEmpty)
              Container(
                height: 2,
                color: AppColors.primary.withValues(alpha: 0.45),
              ),
            LongPressDraggable<TaskDragPayload>(
              data: TaskDragPayload(
                task: task,
                sourceListId: task.taskListId ?? 0,
                sourceDone: task.isDone,
              ),
              feedback: Material(
                elevation: 3,
                borderRadius: BorderRadius.circular(6),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 280),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      task.title.trim().isEmpty
                          ? state.strings['newTaskHint']
                          : task.title,
                      style: AppTypography.noteBodyStyle,
                    ),
                  ),
                ),
              ),
              childWhenDragging: Opacity(
                opacity: 0.35,
                child: TaskRow(
                  task: task,
                  state: state,
                  onToggle: () {},
                  readOnly: true,
                ),
              ),
              child: TaskRow(
                task: task,
                state: state,
                onToggle: () => unawaited(_toggle(task)),
                onTitleChanged: (title) =>
                    unawaited(state.updateTaskTitle(task, title)),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewType = state.selectedViewType;
    if (viewType == null) {
      return Center(child: Text(state.strings['selectView']));
    }

    // Rebuild when AppState notifies.
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final label = state.viewLabel(viewType);
        final tasks = _displayTasks;
        final zones = TaskZones.fromOrdered(tasks);
        final sections = state.sectionsForViewType(viewType);
        final s = state.strings;

        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 96),
          children: [
            Text(label, style: AppTypography.pageTitleStyle),
            const SizedBox(height: 12),
            if (sections.isNotEmpty) ...[
              for (final section in sections) ...[
                Text(section, style: AppTypography.noteTitleStyle),
                const SizedBox(height: 8),
              ],
            ],
            if (tasks.isEmpty)
              Text(s['emptyView'])
            else ...[
              _zoneLabel(s['tasksActive']),
              for (final t in zones.active) _taskTile(t),
              _dropGap(targetDone: false, indexInZone: zones.active.length),
              if (zones.done.isNotEmpty) ...[
                _zoneLabel(s['tasksDone']),
                for (final t in zones.done) _taskTile(t),
                _dropGap(targetDone: true, indexInZone: zones.done.length),
              ],
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final controller = TextEditingController();
                final name = await showAppDialog<String>(
                  context: context,
                  builder: (ctx) => AppAdaptiveDialogShell(
                    title: Text(state.strings.newSectionTitle(label)),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(state.strings['cancel']),
                      ),
                      FilledButton(
                        onPressed: () =>
                            Navigator.pop(ctx, controller.text.trim()),
                        child: Text(state.strings['add']),
                      ),
                    ],
                    child: AppDialogField(
                      label: state.strings['sectionName'],
                      child: TextField(
                        controller: controller,
                        autofocus: true,
                        decoration: DialogFieldStyle.decoration(),
                      ),
                    ),
                  ),
                );
                if (name != null && name.isNotEmpty) {
                  await state.createViewSection(viewType, name);
                }
              },
              icon: const AppIcon(AppIcons.add, size: 16),
              label: Text(state.strings['addSection']),
            ),
          ],
        );
      },
    );
  }
}
