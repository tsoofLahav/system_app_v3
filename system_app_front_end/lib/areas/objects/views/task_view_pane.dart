import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../../core/platform/app_form_factor.dart';
import '../../automations/section_window_editor.dart';
import '../../ui/app_colors.dart';
import '../../ui/app_typography.dart';
import '../../ui/confirm_dialog.dart';
import '../../ux/shell/app_bottom_bar.dart';
import '../../ux/topic/topic_appearance.dart';
import '../../ux/widgets/app_context_menu.dart';
import '../data/task.dart';
import '../data/view_layout.dart';
import '../tasks/task_drag_data.dart';
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
    this.sectionName,
    this.sectionFlag,
    this.topicKey,
    this.accent,
    this.tintSeed = 1,
    this.isImportant = false,
    this.editableSection = false,
  });

  final String key;
  final String title;
  final List<Task> tasks;
  final ViewSectionDef? section;
  final String? sectionName;
  final String? sectionFlag;
  final String? topicKey;
  final Color? accent;
  final int tintSeed;
  final bool isImportant;
  final bool editableSection;
}

/// View page: grid of section/topic frames. Each frame hosts [TaskListSurface]
/// for file-like task interaction; this pane owns placement chrome only.
class TaskViewPane extends StatefulWidget {
  const TaskViewPane({super.key, required this.state});

  final AppState state;

  @override
  State<TaskViewPane> createState() => _TaskViewPaneState();
}

class _TaskViewPaneState extends State<TaskViewPane> {
  var _frameReorderMode = false;
  var _taskReorderMode = false;
  ViewChromeHost? _chromeHost;

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    _publishChrome();
  }

  @override
  void dispose() {
    final host = _chromeHost;
    if (host != null) ViewChromeRegistry.detach(host);
    super.dispose();
  }

  void _publishChrome() {
    final host = ViewChromeHost(
      onToggleDisplayMode: _toggleDisplayMode,
      onAddSection: () => unawaited(_addSection()),
      onStartFrameReorder: _startFrameReorder,
      onToggleTaskReorder: _toggleTaskReorder,
      frameReorderMode: _frameReorderMode,
    );
    _chromeHost = host;
    ViewChromeRegistry.attach(host);
  }

  void _toggleDisplayMode() {
    setState(() {
      _frameReorderMode = false;
      _taskReorderMode = false;
    });
    _publishChrome();
    final next = state.viewDisplayMode == ViewDisplayMode.byTopic
        ? ViewDisplayMode.bySection
        : ViewDisplayMode.byTopic;
    unawaited(state.setViewDisplayMode(next));
  }

  List<Task> get _membershipTasks {
    return [
      for (final m in state.viewMemberships)
        if (state.taskForMembership(m) case final task?)
          if (task.appearsInView) task,
    ];
  }

  List<Task> _sortFrameTasks(List<Task> tasks) {
    if (tasks.length <= 1) return TaskZones.fromOrdered(tasks).all;
    final byTopic = state.viewDisplayMode == ViewDisplayMode.byTopic;
    final byId = {
      for (final m in state.viewMemberships)
        if (m.taskId != null) m.taskId!: m,
    };
    final sorted = [...tasks];
    sorted.sort((a, b) {
      final ma = byId[a.id];
      final mb = byId[b.id];
      final oa = byTopic ? (ma?.topicOrderIndex ?? 0) : (ma?.orderIndex ?? 0);
      final ob = byTopic ? (mb?.topicOrderIndex ?? 0) : (mb?.orderIndex ?? 0);
      final c = oa.compareTo(ob);
      if (c != 0) return c;
      return a.id.compareTo(b.id);
    });
    return TaskZones.fromOrdered(sorted).all;
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
    final membership = state.viewMemberships
        .where((m) => m.taskId == task.id)
        .firstOrNull;
    return ViewLayoutConfig.topicBucketKey(
      hasMembership: membership != null,
      membershipTopicKey: membership?.topicKey,
      taskTopicKey: task.topicKey,
      homeTopicId: task.topicId,
    );
  }

  String _topicTitle(String key, List<Task> tasksInFrame) {
    final s = state.strings;
    if (key == 'no_topic') return s['noTopic'];
    for (final t in tasksInFrame) {
      final name = t.topicName?.trim();
      if (name != null && name.isNotEmpty) {
        return state.strings.displayTopicName(name);
      }
    }
    final id = int.tryParse(key.replaceFirst('topic_', ''));
    final topic = state.allTopics.where((t) => t.id == id).firstOrNull;
    if (topic != null) return state.topicDisplayName(topic);
    return key;
  }

  Color? _topicAccent(String key, List<Task> tasksInFrame) {
    if (key == 'no_topic') return null;
    for (final t in tasksInFrame) {
      if (t.topicColor != null && t.topicColor!.isNotEmpty) {
        return TopicAppearance.colorFromHex(t.topicColor);
      }
    }
    final id = int.tryParse(key.replaceFirst('topic_', ''));
    final topic = state.allTopics.where((t) => t.id == id).firstOrNull;
    return topic == null ? null : TopicAppearance.accentFor(topic);
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

    final byKey = <String, _ViewFrame>{};
    for (final section in sections) {
      final key = 'section:${section.name}';
      byKey[key] = _ViewFrame(
        key: key,
        title: section.name,
        tasks: _sortFrameTasks(bySection[section.name] ?? const []),
        section: section,
        sectionName: section.name,
        sectionFlag: section.flag,
        accent: state.sectionAccent(section),
        tintSeed: _stableSeed(section.name),
        isImportant: section.isImportant,
        editableSection: true,
      );
      bySection.remove(section.name);
    }
    for (final entry in bySection.entries) {
      final key = 'section:${entry.key}';
      byKey[key] = _ViewFrame(
        key: key,
        title: entry.key,
        tasks: _sortFrameTasks(entry.value),
        section: ViewSectionDef(name: entry.key),
        sectionName: entry.key,
        tintSeed: _stableSeed(entry.key),
        editableSection: true,
      );
    }
    if (uncategorized.isNotEmpty) {
      byKey['section:'] = _ViewFrame(
        key: 'section:',
        title: s['uncategorized'],
        tasks: _sortFrameTasks(uncategorized),
        tintSeed: 1,
      );
    }

    final preferred = state.selectedView == null
        ? const <String>[]
        : ViewLayoutConfig.sectionOrder(state.selectedView!.layoutConfig);
    final keys = <String>[];
    final seen = <String>{};
    for (final k in preferred) {
      if (!byKey.containsKey(k)) continue;
      if (seen.add(k)) keys.add(k);
    }
    // Fallback: defined/orphan section order, then uncategorized once.
    for (final section in sections) {
      final k = 'section:${section.name}';
      if (seen.add(k)) keys.add(k);
    }
    for (final k in byKey.keys) {
      if (k == 'section:') continue;
      if (seen.add(k)) keys.add(k);
    }
    if (byKey.containsKey('section:') && seen.add('section:')) {
      keys.add('section:');
    }

    return [for (final k in keys) byKey[k]!];
  }

  List<_ViewFrame> _framesForTopics(List<Task> tasks) {
    final byTopic = <String, List<Task>>{};
    for (final t in tasks) {
      (byTopic[_topicKeyFor(t)] ??= []).add(t);
    }

    final preferred = state.selectedView == null
        ? const <String>[]
        : ViewLayoutConfig.topicOrder(state.selectedView!.layoutConfig);
    // Dedupe. Prefer saved order (including no_topic if the user moved it);
    // append no_topic once at the end only when it was never listed.
    final keys = <String>[];
    final seen = <String>{};
    for (final k in preferred) {
      if (k == 'no_topic') {
        if (byTopic['no_topic']?.isEmpty ?? true) continue;
      } else if (!byTopic.containsKey(k)) {
        continue;
      }
      if (seen.add(k)) keys.add(k);
    }
    for (final k in byTopic.keys) {
      if (k == 'no_topic') continue;
      if (seen.add(k)) keys.add(k);
    }
    if ((byTopic['no_topic']?.isNotEmpty ?? false) && seen.add('no_topic')) {
      keys.add('no_topic');
    }

    return [
      for (final key in keys)
        _ViewFrame(
          key: 'topic:$key',
          title: _topicTitle(key, byTopic[key] ?? const []),
          tasks: _sortFrameTasks(byTopic[key] ?? const []),
          topicKey: key == 'no_topic' ? null : key,
          accent: _topicAccent(key, byTopic[key] ?? const []),
          tintSeed: key == 'no_topic'
              ? 1
              : ((byTopic[key]?.isNotEmpty ?? false)
                        ? byTopic[key]!.first.topicId
                        : null) ??
                    _stableSeed(key),
        ),
    ];
  }

  Future<void> _onForeignDrop({
    required _ViewFrame frame,
    required TaskDragPayload payload,
    required bool targetDone,
    required int indexInZone,
  }) async {
    final byTopic = state.viewDisplayMode == ViewDisplayMode.byTopic;
    try {
      if (byTopic) {
        await state.updateViewTaskPlacement(
          taskId: payload.task.id,
          topicKey: frame.topicKey,
          clearTopic: frame.topicKey == null,
          notify: false,
        );
      } else {
        await state.updateViewTaskPlacement(
          taskId: payload.task.id,
          sectionName: frame.sectionName,
          sectionFlag: frame.sectionFlag ?? frame.section?.flag,
          clearSection: frame.sectionName == null,
          notify: false,
        );
      }
      if (payload.task.isDone != targetDone) {
        await state.toggleTaskStatus(payload.task, notify: false);
      }

      final moved = payload.task.copyWith(
        status: targetDone ? 'done' : 'active',
      );
      final others = [
        for (final t in frame.tasks)
          if (t.id != moved.id) t,
      ];
      final next = TaskZones.fromOrdered(
        others,
      ).inserted(task: moved, targetDone: targetDone, indexInZone: indexInZone);
      final frameOrdered = next.orderedIds;
      final frameIndex = {
        for (var i = 0; i < frameOrdered.length; i++) frameOrdered[i]: i,
      };

      final memberships = <Map<String, dynamic>>[];
      for (final m in state.viewMemberships) {
        final isDropped = m.taskId == moved.id;
        final at = m.taskId == null ? null : frameIndex[m.taskId];
        memberships.add({
          ...m.toReplaceJson(),
          if (isDropped && !byTopic) 'section_name': frame.sectionName,
          if (isDropped && !byTopic)
            'section_flag': frame.sectionFlag ?? frame.section?.flag,
          if (isDropped && byTopic) 'topic_key': frame.topicKey,
          if (!byTopic && at != null) 'order_index': at,
          if (byTopic && at != null) 'topic_order_index': at,
        });
      }
      await state.reorderViewMemberships(memberships, notify: false);
      await state.refreshOpenTaskSurfaces(notify: true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(state.strings['reorderFailed'])));
      await state.refreshOpenTaskSurfaces(notify: true);
    }
  }

  Future<void> _addSection() async {
    final viewType = state.selectedViewType;
    if (viewType == null) return;
    final next = await showViewSectionDialog(
      context: context,
      state: state,
      viewLabel: state.viewLabel(viewType),
    );
    if (next == null || next.name.trim().isEmpty) return;
    await state.createViewSection(
      viewType,
      next.name,
      flag: next.flag,
      colorHex: next.colorHex,
      key: next.key,
      cadence: next.cadence,
      isDefault: next.isDefault,
    );
  }

  Future<void> _editSection(ViewSectionDef section) async {
    final next = await showViewSectionDialog(
      context: context,
      state: state,
      section: section,
    );
    if (next == null) return;
    await state.updateViewSection(oldName: section.name, next: next);
  }

  Future<void> _onSectionTitleMenu(
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
          value: 'automation',
          label: s['openSectionAutomation'],
        ),
        AppContextMenuItem(
          value: 'delete',
          label: s['deleteSection'],
          destructive: true,
        ),
      ],
    );
    if (!mounted || action == null) return;
    if (action == 'edit') {
      await _editSection(section);
      return;
    }
    if (action == 'automation') {
      await _openSectionAutomation(section);
      return;
    }
    if (action == 'delete') {
      await _deleteSection(section);
    }
  }

  Future<void> _openSectionAutomation(ViewSectionDef section) async {
    final view = state.selectedView;
    final key = section.key;
    if (view == null || key == null || key.isEmpty) return;
    await state.loadAutomations();
    if (!mounted) return;
    final window = state.sectionWindowFor(viewId: view.id, sectionKey: key);
    if (window == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(state.strings['sectionAutomationMissing'])),
      );
      return;
    }
    await showSectionWindowEditor(
      context: context,
      state: state,
      automation: window,
    );
  }

  Future<void> _deleteSection(ViewSectionDef section) async {
    final s = state.strings;
    final ok = await showAppConfirmDialog(
      context: context,
      title: s['deleteSectionTitle'],
      message: s['deleteSectionBody'],
      confirmLabel: s['delete'],
      cancelLabel: s['cancel'],
      destructive: true,
    );
    if (!ok || !mounted) return;
    await state.deleteViewSection(section.name);
  }

  Future<void> _applyFrameOrder(List<_ViewFrame> ordered) async {
    if (state.viewDisplayMode == ViewDisplayMode.byTopic) {
      final seen = <String>{};
      final keys = <String>[
        for (final f in ordered)
          if (f.key.startsWith('topic:'))
            if (seen.add(f.key.substring('topic:'.length)))
              f.key.substring('topic:'.length),
      ];
      await state.reorderViewTopicKeys(keys);
      return;
    }
    // Frame keys (`section:<name>`, `section:` for uncategorized) — own order
    // from topic mode's `topic_order`.
    final seen = <String>{};
    final keys = <String>[
      for (final f in ordered)
        if (f.key.startsWith('section:') && seen.add(f.key)) f.key,
    ];
    await state.reorderViewSectionKeys(keys);
  }

  void _exitFrameReorder() {
    if (!_frameReorderMode) return;
    setState(() => _frameReorderMode = false);
    _publishChrome();
  }

  void _startFrameReorder() {
    setState(() {
      _taskReorderMode = false;
      _frameReorderMode = true;
    });
    _publishChrome();
  }

  void _toggleTaskReorder() {
    setState(() {
      _frameReorderMode = false;
      _taskReorderMode = !_taskReorderMode;
    });
    _publishChrome();
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
        final tasks = _membershipTasks;
        final byTopic = state.viewDisplayMode == ViewDisplayMode.byTopic;
        final frames = byTopic
            ? _framesForTopics(tasks)
            : _framesForSections(tasks);

        Widget grid = _FrameGrid(
          frames: frames,
          frameReorderMode: _frameReorderMode,
          taskReorderMode: _taskReorderMode,
          state: state,
          onForeignDrop: _onForeignDrop,
          onTaskReorderModeChanged: (value) {
            setState(() => _taskReorderMode = value);
          },
          onSectionTitleMenu: _onSectionTitleMenu,
          onEditSection: _editSection,
          onDeleteSection: _deleteSection,
          onMoveFrame: (fromKey, toKey) => _moveFrame(frames, fromKey, toKey),
          onExitFrameReorder: _exitFrameReorder,
        );

        // Task reorder: tap outside the grid ends the mode.
        if (_taskReorderMode && !_frameReorderMode) {
          grid = TapRegion(
            onTapOutside: (_) => setState(() => _taskReorderMode = false),
            child: grid,
          );
        }

        return Stack(
          children: [
            Positioned.fill(
              child: ListView(
                physics: _frameReorderMode
                    ? const NeverScrollableScrollPhysics()
                    : null,
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.canvasPadding.left,
                  AppSpacing.canvasPadding.top,
                  AppSpacing.canvasPadding.right,
                  AppSpacing.canvasPadding.bottom +
                      (isPhoneLayout
                          ? 52
                          : AppBottomBarMetrics.scrollInset + 52),
                ),
                children: [
                  // Frame reorder exits on empty canvas (title / space around
                  // frames), not via the chrome button — and not TapRegion,
                  // which used to cancel mid-drag drops.
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _frameReorderMode ? _exitFrameReorder : null,
                    child: Text(label, style: AppTypography.pageTitleStyle),
                  ),
                  SizedBox(
                    height: 16,
                    child: _frameReorderMode
                        ? GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _exitFrameReorder,
                          )
                        : null,
                  ),
                  grid,
                  if (_frameReorderMode)
                    SizedBox(
                      height: MediaQuery.sizeOf(context).height,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _exitFrameReorder,
                      ),
                    ),
                ],
              ),
            ),
            // Dimmed full-bleed catcher behind chrome only — taps on the bar
            // outside its icons still fall through to ListView below when the
            // bar doesn't fill width; center chrome stays tappable to *start*
            // reorder without acting as the exit control.
            if (!isPhoneLayout)
              Positioned(
                left: 0,
                right: 0,
                bottom: AppBottomBarMetrics.scrollInset + 4,
                child: Center(
                  child: ViewChromeMenu(
                    state: state,
                    displayMode: state.viewDisplayMode,
                    frameReorderMode: _frameReorderMode,
                    onToggleDisplayMode: _toggleDisplayMode,
                    onAddSection: () => unawaited(_addSection()),
                    onStartFrameReorder: _startFrameReorder,
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
    required this.taskReorderMode,
    required this.state,
    required this.onForeignDrop,
    required this.onTaskReorderModeChanged,
    required this.onSectionTitleMenu,
    required this.onEditSection,
    required this.onDeleteSection,
    required this.onMoveFrame,
    required this.onExitFrameReorder,
  });

  final List<_ViewFrame> frames;
  final bool frameReorderMode;
  final bool taskReorderMode;
  final AppState state;
  final void Function({
    required _ViewFrame frame,
    required TaskDragPayload payload,
    required bool targetDone,
    required int indexInZone,
  })
  onForeignDrop;
  final ValueChanged<bool> onTaskReorderModeChanged;
  final Future<void> Function(Offset, ViewSectionDef) onSectionTitleMenu;
  final Future<void> Function(ViewSectionDef) onEditSection;
  final Future<void> Function(ViewSectionDef) onDeleteSection;
  final void Function(String fromKey, String toKey) onMoveFrame;
  final VoidCallback onExitFrameReorder;

  static const frameWidth = 260.0;
  static const gap = 12.0;

  @override
  Widget build(BuildContext context) {
    final wrap = Wrap(
      spacing: gap,
      runSpacing: gap,
      children: [
        for (final frame in frames)
          SizedBox(
            key: ValueKey(frame.key),
            width: frameWidth,
            child: _DraggableFrame(
              frame: frame,
              frameReorderMode: frameReorderMode,
              taskReorderMode: taskReorderMode,
              state: state,
              onForeignDrop: onForeignDrop,
              onTaskReorderModeChanged: onTaskReorderModeChanged,
              onSectionTitleMenu: onSectionTitleMenu,
              onEditSection: onEditSection,
              onDeleteSection: onDeleteSection,
              onMoveFrame: onMoveFrame,
            ),
          ),
      ],
    );
    if (!frameReorderMode) return wrap;
    // Gaps / empty space inside the grid bounds exit reorder; frames sit
    // above and absorb their own pointer events (including mid-drag).
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onExitFrameReorder,
          ),
        ),
        wrap,
      ],
    );
  }
}

class _DraggableFrame extends StatelessWidget {
  const _DraggableFrame({
    required this.frame,
    required this.frameReorderMode,
    required this.taskReorderMode,
    required this.state,
    required this.onForeignDrop,
    required this.onTaskReorderModeChanged,
    required this.onSectionTitleMenu,
    required this.onEditSection,
    required this.onDeleteSection,
    required this.onMoveFrame,
  });

  final _ViewFrame frame;
  final bool frameReorderMode;
  final bool taskReorderMode;
  final AppState state;
  final void Function({
    required _ViewFrame frame,
    required TaskDragPayload payload,
    required bool targetDone,
    required int indexInZone,
  })
  onForeignDrop;
  final ValueChanged<bool> onTaskReorderModeChanged;
  final Future<void> Function(Offset, ViewSectionDef) onSectionTitleMenu;
  final Future<void> Function(ViewSectionDef) onEditSection;
  final Future<void> Function(ViewSectionDef) onDeleteSection;
  final void Function(String fromKey, String toKey) onMoveFrame;

  @override
  Widget build(BuildContext context) {
    final section = frame.section;
    final canEditSection = frame.editableSection && section != null;
    final card = ViewListFrame(
      state: state,
      title: frame.title,
      tasks: frame.tasks,
      sectionName: frame.sectionName,
      sectionFlag: frame.sectionFlag,
      topicKey: frame.topicKey,
      onSectionTitleMenu: canEditSection
          ? (d) => unawaited(onSectionTitleMenu(d.globalPosition, section))
          : null,
      accent: frame.accent,
      tintSeed: frame.tintSeed,
      isImportant: frame.isImportant,
      attention:
          frame.section != null &&
          state.selectedView != null &&
          state.sectionHasAttention(
            viewId: state.selectedView!.id,
            sectionKey: frame.section!.key,
          ),
      frameReorderMode: frameReorderMode,
      taskReorderMode: taskReorderMode,
      onTaskReorderModeChanged: onTaskReorderModeChanged,
      onForeignDrop:
          ({required payload, required targetDone, required indexInZone}) =>
              onForeignDrop(
                frame: frame,
                payload: payload,
                targetDone: targetDone,
                indexInZone: indexInZone,
              ),
    );

    if (!frameReorderMode) return card;

    return DragTarget<ViewFrameDragPayload>(
      onWillAcceptWithDetails: (d) => d.data.frameKey != frame.key,
      onAcceptWithDetails: (d) => onMoveFrame(d.data.frameKey, frame.key),
      builder: (context, candidate, rejected) {
        final hot = candidate.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: hot
                ? Border.all(
                    color: AppColors.primary.withValues(alpha: 0.45),
                    width: 1.5,
                  )
                : null,
          ),
          child: Draggable<ViewFrameDragPayload>(
            data: ViewFrameDragPayload(frameKey: frame.key),
            feedback: Material(
              color: Colors.transparent,
              elevation: 6,
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: _FrameGrid.frameWidth,
                child: Opacity(opacity: 0.94, child: card),
              ),
            ),
            childWhenDragging: Opacity(opacity: 0.3, child: card),
            child: MouseRegion(cursor: SystemMouseCursors.grab, child: card),
          ),
        );
      },
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
