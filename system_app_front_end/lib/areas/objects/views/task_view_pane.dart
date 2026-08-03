import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../ui/adaptive_dialog.dart';
import '../../ui/app_colors.dart';
import '../../ui/app_typography.dart';
import '../../ui/dialog_field_style.dart';
import '../../ux/shell/app_bottom_bar.dart';
import '../../ux/topic/topic_appearance.dart';
import '../../ux/widgets/app_context_menu.dart';
import '../data/task.dart';
import '../data/view_layout.dart';
import '../tasks/task_zones.dart';
import './edit_view_section_dialog.dart';
import './view_chrome_menu.dart';
import './view_list_frame.dart';

class _ViewFrame {
  const _ViewFrame({
    required this.key,
    required this.title,
    required this.tasks,
    this.section,
    this.accent,
    this.tintSeed = 1,
    this.isImportant = false,
    this.editableSection = false,
  });

  final String key;
  final String title;
  final List<Task> tasks;
  final ViewSectionDef? section;
  final Color? accent;
  final int tintSeed;
  final bool isImportant;
  final bool editableSection;
}

class TaskViewPane extends StatefulWidget {
  const TaskViewPane({super.key, required this.state});

  final AppState state;

  @override
  State<TaskViewPane> createState() => _TaskViewPaneState();
}

class _TaskViewPaneState extends State<TaskViewPane> {
  List<Task>? _optimisticTasks;
  var _persisting = false;
  var _frameReorderMode = false;

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

  int _stableSeed(String key) {
    var h = 0;
    for (final c in key.codeUnits) {
      h = 0x1fffffff & (h * 31 + c);
    }
    return h == 0 ? 1 : h.abs();
  }

  String? _sectionNameForTask(Task task) {
    for (final m in state.viewMemberships) {
      if (m.taskId == task.id) return m.sectionName;
    }
    return task.sectionName;
  }

  String _topicKeyFor(Task task) {
    if (task.topicKey != null && task.topicKey!.isNotEmpty) {
      return task.topicKey!;
    }
    if (task.topicId != null) return 'topic_${task.topicId}';
    return 'no_topic';
  }

  List<_ViewFrame> _framesForSections(List<Task> tasks) {
    final s = state.strings;
    final sections = state.sectionsForSelectedView();
    final bySection = <String, List<Task>>{};
    final uncategorized = <Task>[];

    for (final t in tasks) {
      final name = _sectionNameForTask(t)?.trim();
      if (name == null || name.isEmpty) {
        uncategorized.add(t);
      } else {
        (bySection[name] ??= []).add(t);
      }
    }

    final frames = <_ViewFrame>[];
    for (final section in sections) {
      frames.add(
        _ViewFrame(
          key: 'section:${section.name}',
          title: section.name,
          tasks: bySection[section.name] ?? const [],
          section: section,
          accent: state.sectionAccent(section),
          tintSeed: _stableSeed(section.name),
          isImportant: section.isImportant,
          editableSection: true,
        ),
      );
      bySection.remove(section.name);
    }
    for (final entry in bySection.entries) {
      frames.add(
        _ViewFrame(
          key: 'section:${entry.key}',
          title: entry.key,
          tasks: entry.value,
          section: ViewSectionDef(name: entry.key),
          tintSeed: _stableSeed(entry.key),
          editableSection: true,
        ),
      );
    }
    if (uncategorized.isNotEmpty || frames.isEmpty) {
      frames.add(
        _ViewFrame(
          key: 'section:',
          title: s['uncategorized'],
          tasks: uncategorized,
          tintSeed: 1,
        ),
      );
    }
    return frames;
  }

  List<_ViewFrame> _framesForTopics(List<Task> tasks) {
    final s = state.strings;
    final byTopic = <String, List<Task>>{};
    for (final t in tasks) {
      (byTopic[_topicKeyFor(t)] ??= []).add(t);
    }

    final preferred = state.selectedView == null
        ? const <String>[]
        : ViewLayoutConfig.topicOrder(state.selectedView!.layoutConfig);
    final keys = <String>[
      for (final k in preferred)
        if (byTopic.containsKey(k)) k,
      for (final k in byTopic.keys)
        if (!preferred.contains(k) && k != 'no_topic') k,
      if (byTopic.containsKey('no_topic')) 'no_topic',
    ];

    return [
      for (final key in keys)
        _ViewFrame(
          key: 'topic:$key',
          title: key == 'no_topic'
              ? s['noTopic']
              : (byTopic[key]!.first.topicName?.trim().isNotEmpty == true
                  ? byTopic[key]!.first.topicName!
                  : key),
          tasks: byTopic[key] ?? const [],
          accent: key == 'no_topic'
              ? null
              : TopicAppearance.colorFromHex(byTopic[key]!.first.topicColor),
          tintSeed: key == 'no_topic'
              ? 1
              : (byTopic[key]!.first.topicId ?? _stableSeed(key)),
        ),
    ];
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
        'topic_key': existing?.topicKey ?? t.topicKey,
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

  List<Task> _mergeFrameOrder({
    required List<Task> all,
    required Set<int> frameIds,
    required List<Task> newFrameOrder,
  }) {
    final queue = List<Task>.of(newFrameOrder);
    final out = <Task>[];
    for (final t in all) {
      if (frameIds.contains(t.id)) {
        if (queue.isNotEmpty) out.add(queue.removeAt(0));
      } else {
        out.add(t);
      }
    }
    out.addAll(queue);
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
      if (mounted) setState(() => _optimisticTasks = null);
    } catch (_) {
      if (!mounted) return;
      setState(() => _optimisticTasks = snapshot.all);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(state.strings['reorderFailed'])),
      );
    } finally {
      _persisting = false;
    }
  }

  void _onFrameZonesChanged(_ViewFrame frame, TaskZones nextZones) {
    final all = _displayTasks;
    final snapshot = TaskZones.fromOrdered(all);
    final frameIds = {for (final t in frame.tasks) t.id};
    final merged = _mergeFrameOrder(
      all: all,
      frameIds: frameIds,
      newFrameOrder: nextZones.all,
    );
    final byId = {for (final t in nextZones.all) t.id: t};
    final withStatus = [for (final t in merged) byId[t.id] ?? t];
    final next = TaskZones.fromOrdered(withStatus);
    setState(() => _optimisticTasks = next.all);
    unawaited(_persistZones(next, snapshot));
  }

  Future<void> _addSection() async {
    final viewType = state.selectedViewType;
    if (viewType == null) return;
    final label = state.viewLabel(viewType);
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
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
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
  }

  Future<void> _editSection(ViewSectionDef section) async {
    final next = await showEditViewSectionDialog(
      context: context,
      state: state,
      section: section,
    );
    if (next == null) return;
    await state.updateViewSection(oldName: section.name, next: next);
  }

  Future<void> _onSectionContextMenu(
    Offset globalPosition,
    ViewSectionDef section,
  ) async {
    final s = state.strings;
    final action = await AppContextMenu.show(
      context: context,
      globalPosition: globalPosition,
      isRtl: s.isRtl,
      entries: [
        AppContextMenuItem(value: 'edit', label: s['editSection']),
        AppContextMenuItem(
          value: 'flag',
          label: section.isImportant
              ? s['unmarkSectionImportant']
              : s['markSectionImportant'],
        ),
        AppContextMenuItem(value: 'color', label: s['sectionColor']),
      ],
    );
    if (!mounted || action == null) return;
    if (action == 'edit' || action == 'color') {
      await _editSection(section);
      return;
    }
    if (action == 'flag') {
      await state.setViewSectionImportance(section.name, !section.isImportant);
    }
  }

  Future<void> _applyFrameOrder(List<_ViewFrame> ordered) async {
    if (state.viewDisplayMode == ViewDisplayMode.byTopic) {
      final keys = [
        for (final f in ordered)
          if (f.key.startsWith('topic:')) f.key.substring('topic:'.length),
      ];
      await state.reorderViewTopicKeys(keys);
      return;
    }
    final defs = [
      for (var i = 0; i < ordered.length; i++)
        if (ordered[i].section != null)
          ordered[i].section!.copyWith(orderIndex: i),
    ];
    if (defs.isEmpty) return;
    await state.replaceViewSections(defs);
  }

  void _moveFrame(List<_ViewFrame> frames, String fromKey, String toKey) {
    final from = frames.indexWhere((f) => f.key == fromKey);
    final to = frames.indexWhere((f) => f.key == toKey);
    if (from < 0 || to < 0 || from == to) return;
    final next = [...frames];
    final item = next.removeAt(from);
    next.insert(to, item);
    unawaited(_applyFrameOrder(next));
  }

  @override
  Widget build(BuildContext context) {
    final viewType = state.selectedViewType;
    if (viewType == null) {
      return Center(child: Text(state.strings['selectView']));
    }

    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final label = state.viewLabel(viewType);
        final tasks = _displayTasks;
        final byTopic = state.viewDisplayMode == ViewDisplayMode.byTopic;
        final frames =
            byTopic ? _framesForTopics(tasks) : _framesForSections(tasks);
        final s = state.strings;

        Widget grid = _FrameGrid(
          frames: frames,
          frameReorderMode: _frameReorderMode,
          state: state,
          onZonesChanged: _onFrameZonesChanged,
          onSectionMenu: _onSectionContextMenu,
          onMoveFrame: (fromKey, toKey) => _moveFrame(frames, fromKey, toKey),
        );

        if (_frameReorderMode) {
          grid = TapRegion(
            onTapOutside: (_) => setState(() => _frameReorderMode = false),
            child: grid,
          );
        }

        return Stack(
          children: [
            Positioned.fill(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.canvasPadding.left,
                  AppSpacing.canvasPadding.top,
                  AppSpacing.canvasPadding.right,
                  AppSpacing.canvasPadding.bottom +
                      AppBottomBarMetrics.scrollInset +
                      52,
                ),
                children: [
                  Text(label, style: AppTypography.pageTitleStyle),
                  const SizedBox(height: 16),
                  if (tasks.isEmpty && frames.every((f) => f.tasks.isEmpty))
                    Text(
                      s.noTasksInView(label),
                      style: AppTypography.metaStyle.copyWith(
                        color: AppColors.textHint,
                      ),
                    )
                  else
                    grid,
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: AppBottomBarMetrics.scrollInset + 4,
              child: Center(
                child: ViewChromeMenu(
                  state: state,
                  displayMode: state.viewDisplayMode,
                  frameReorderMode: _frameReorderMode,
                  onDisplayMode: (mode) {
                    setState(() => _frameReorderMode = false);
                    unawaited(state.setViewDisplayMode(mode));
                  },
                  onAddSection: () => unawaited(_addSection()),
                  onToggleFrameReorder: () {
                    setState(() => _frameReorderMode = !_frameReorderMode);
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FrameGrid extends StatelessWidget {
  const _FrameGrid({
    required this.frames,
    required this.frameReorderMode,
    required this.state,
    required this.onZonesChanged,
    required this.onSectionMenu,
    required this.onMoveFrame,
  });

  final List<_ViewFrame> frames;
  final bool frameReorderMode;
  final AppState state;
  final void Function(_ViewFrame frame, TaskZones zones) onZonesChanged;
  final Future<void> Function(Offset, ViewSectionDef) onSectionMenu;
  final void Function(String fromKey, String toKey) onMoveFrame;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 960 ? 3 : (width >= 620 ? 2 : 1);
        const gap = 14.0;
        final tileWidth = columns == 1
            ? width
            : (width - gap * (columns - 1)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final frame in frames)
              SizedBox(
                width: tileWidth,
                child: _DraggableFrame(
                  frame: frame,
                  frameReorderMode: frameReorderMode,
                  state: state,
                  onZonesChanged: onZonesChanged,
                  onSectionMenu: onSectionMenu,
                  onMoveFrame: onMoveFrame,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _DraggableFrame extends StatelessWidget {
  const _DraggableFrame({
    required this.frame,
    required this.frameReorderMode,
    required this.state,
    required this.onZonesChanged,
    required this.onSectionMenu,
    required this.onMoveFrame,
  });

  final _ViewFrame frame;
  final bool frameReorderMode;
  final AppState state;
  final void Function(_ViewFrame frame, TaskZones zones) onZonesChanged;
  final Future<void> Function(Offset, ViewSectionDef) onSectionMenu;
  final void Function(String fromKey, String toKey) onMoveFrame;

  @override
  Widget build(BuildContext context) {
    final card = ViewListFrame(
      state: state,
      title: frame.title,
      tasks: frame.tasks,
      accent: frame.accent,
      tintSeed: frame.tintSeed,
      isImportant: frame.isImportant,
      frameReorderMode: frameReorderMode,
      onZonesChanged: (zones) => onZonesChanged(frame, zones),
      onSecondaryTapDown: frame.editableSection && frame.section != null
          ? (d) => unawaited(onSectionMenu(d.globalPosition, frame.section!))
          : null,
    );

    if (!frameReorderMode) return card;

    return DragTarget<ViewFrameDragPayload>(
      onWillAcceptWithDetails: (d) => d.data.frameKey != frame.key,
      onAcceptWithDetails: (d) => onMoveFrame(d.data.frameKey, frame.key),
      builder: (context, candidate, rejected) {
        return Column(
          children: [
            if (candidate.isNotEmpty)
              Container(
                height: 4,
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            LongPressDraggable<ViewFrameDragPayload>(
              data: ViewFrameDragPayload(frameKey: frame.key),
              feedback: Material(
                color: Colors.transparent,
                elevation: 4,
                child: SizedBox(
                  width: 260,
                  child: Opacity(opacity: 0.92, child: card),
                ),
              ),
              childWhenDragging: Opacity(opacity: 0.35, child: card),
              child: MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: card,
              ),
            ),
          ],
        );
      },
    );
  }
}
