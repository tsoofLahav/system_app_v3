import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/models/task.dart';
import '../../core/task_list_order.dart';
import '../../core/models/view_pane_sync_context.dart';
import '../../core/models/view_section.dart';
import '../../core/registry/task_view_display.dart';
import '../../design_system/app_colors.dart';
import '../../design_system/app_icons.dart';
import '../../design_system/app_typography.dart';
import '../../design_system/glass_surface.dart';
import '../../design_system/note_widgets.dart';
import '../shell/app_bottom_bar.dart';
import 'view_pane_tasks_editor.dart';

class TaskViewPane extends StatefulWidget {
  const TaskViewPane({super.key, required this.state});

  final AppState state;

  @override
  State<TaskViewPane> createState() => _TaskViewPaneState();
}

class _TaskViewPaneState extends State<TaskViewPane> {
  final _sectionController = TextEditingController();

  @override
  void dispose() {
    _sectionController.dispose();
    super.dispose();
  }

  Future<void> _addSection(String viewType) async {
    final name = _sectionController.text.trim();
    if (name.isEmpty) return;
    await widget.state.createViewSection(viewType, name);
    _sectionController.clear();
    if (mounted) Navigator.pop(context);
  }

  void _showAddSectionDialog(String viewType) {
    final s = widget.state.strings;
    showDialog<void>(
      context: context,
      builder: (ctx) => AppGlassDialog(
        title: Text(s.newSectionTitle(widget.state.viewLabel(viewType))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s['cancel']),
          ),
          FilledButton(
            onPressed: () => _addSection(viewType),
            child: Text(s['add']),
          ),
        ],
        child: TextField(
          controller: _sectionController,
          autofocus: true,
          decoration: InputDecoration(labelText: s['sectionName']),
          onSubmitted: (_) => _addSection(viewType),
        ),
      ),
    );
  }

  static const _uncategorizedKey = '__uncategorized__';

  @override
  Widget build(BuildContext context) {
    final viewType = widget.state.selectedViewType;
    if (viewType == null) {
      return Center(child: Text(widget.state.strings['selectView']));
    }

    final s = widget.state.strings;
    final label = widget.state.viewLabel(viewType);
    final tasks = widget.state.viewTasks;
    final sections = widget.state.sectionsForViewType(viewType);
    final displayMode = widget.state.viewDisplayMode;

    if (widget.state.loading && tasks.isEmpty && sections.isEmpty) {
      return TopicCanvasBackground(
        accent: AppColors.text,
        isMain: true,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              Text(label, style: AppTypography.noteTitleStyle),
            ],
          ),
        ),
      );
    }

    return TopicCanvasBackground(
      accent: AppColors.text,
      isMain: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsetsDirectional.fromSTEB(24, 20, 24, 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: AppColors.noteBorder.withValues(alpha: 0.6),
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTypography.pageTitleStyle),
                const SizedBox(height: 12),
                Row(
                  children: [
                    SegmentedButton<TaskViewDisplayMode>(
                      segments: [
                        ButtonSegment(
                          value: TaskViewDisplayMode.bySection,
                          label: Text(s['bySection']),
                        ),
                        ButtonSegment(
                          value: TaskViewDisplayMode.byTopic,
                          label: Text(s['byTopic']),
                        ),
                      ],
                      selected: {displayMode},
                      onSelectionChanged: (s) =>
                          widget.state.setViewDisplayMode(s.first),
                    ),
                    if (displayMode == TaskViewDisplayMode.bySection) ...[
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () => _showAddSectionDialog(viewType),
                        icon: const AppIcon(AppIcons.add, size: 16),
                        label: Text(s['addSection']),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.text,
                        ),
                      ),
                    ],
                  ],
                ),
                if (displayMode == TaskViewDisplayMode.bySection &&
                    sections.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 36,
                    child: ReorderableListView.builder(
                      scrollDirection: Axis.horizontal,
                      buildDefaultDragHandles: false,
                      onReorder: (from, to) {
                        if (to > from) to -= 1;
                        widget.state.reorderViewSections(viewType, from, to);
                      },
                      itemCount: sections.length,
                      itemBuilder: (context, index) {
                        final section = sections[index];
                        return ReorderableDragStartListener(
                          key: ValueKey(section.id),
                          index: index,
                          child: Padding(
                            padding: const EdgeInsetsDirectional.only(end: 6),
                            child: _SectionChip(
                              section: section,
                              onToggleImportance: () =>
                                  widget.state.setViewSectionImportance(
                                section,
                                important: !section.isImportant,
                              ),
                              onDelete: () =>
                                  widget.state.deleteViewSection(section),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: tasks.isEmpty && sections.isEmpty
                ? Center(
                    child: Text(
                      s.noTasksInView(label),
                      style: AppTypography.noteBodyStyle,
                      textAlign: TextAlign.center,
                    ),
                  )
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: AppSpacing.canvasPadding.copyWith(
                      bottom:
                          AppSpacing.canvasPadding.bottom +
                          AppBottomBarMetrics.scrollInset,
                    ),
                    child: displayMode == TaskViewDisplayMode.bySection
                        ? _buildSectionPanes(tasks, sections, viewType)
                        : _buildTopicPanes(tasks, viewType),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionPanes(
    List<Task> tasks,
    List<ViewSection> sections,
    String viewType,
  ) {
    final grouped = <String, List<Task>>{};
    for (final section in sections) {
      grouped[section.name] = [];
    }
    grouped.putIfAbsent(_uncategorizedKey, () => []);

    for (final task in tasks) {
      final key = task.sectionName ?? _uncategorizedKey;
      grouped.putIfAbsent(key, () => []);
      grouped[key]!.add(task);
    }

    final panes = <Widget>[];
    final s = widget.state.strings;

    String paneTitle(String key) =>
        key == _uncategorizedKey ? s['uncategorized'] : key;

    for (final section in sections) {
      panes.add(
        _TaskGroupPane(
          key: ValueKey('section-${section.id}'),
          title: paneTitle(section.name),
          tasks: sortTasksById(grouped[section.name] ?? []),
          state: widget.state,
          viewType: viewType,
          displayMode: TaskViewDisplayMode.bySection,
          sectionName: section.name,
          isImportant: section.isImportant,
          onToggleImportance: () => widget.state.setViewSectionImportance(
            section,
            important: !section.isImportant,
          ),
        ),
      );
    }

    if ((grouped[_uncategorizedKey] ?? []).isNotEmpty) {
      panes.add(
        _TaskGroupPane(
          key: const ValueKey('section-uncategorized'),
          title: s['uncategorized'],
          tasks: sortTasksById(grouped[_uncategorizedKey]!),
          state: widget.state,
          viewType: viewType,
          displayMode: TaskViewDisplayMode.bySection,
        ),
      );
    }

    for (final entry in grouped.entries) {
      if (entry.key == _uncategorizedKey) continue;
      if (sections.any((s) => s.name == entry.key)) continue;
      if (entry.value.isEmpty) continue;
      panes.add(
        _TaskGroupPane(
          key: ValueKey('section-extra-${entry.key}'),
          title: entry.key,
          tasks: sortTasksById(entry.value),
          state: widget.state,
          viewType: viewType,
          displayMode: TaskViewDisplayMode.bySection,
          sectionName: entry.key,
        ),
      );
    }

    if (panes.isEmpty && sections.isNotEmpty) {
      for (final section in sections) {
        panes.add(
          _TaskGroupPane(
            key: ValueKey('section-empty-${section.id}'),
            title: paneTitle(section.name),
            tasks: const [],
            state: widget.state,
            viewType: viewType,
            displayMode: TaskViewDisplayMode.bySection,
            sectionName: section.name,
            isImportant: section.isImportant,
            onToggleImportance: () => widget.state.setViewSectionImportance(
              section,
              important: !section.isImportant,
            ),
          ),
        );
      }
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < panes.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.md),
          panes[i],
        ],
      ],
    );
  }

  Widget _buildTopicPanes(List<Task> tasks, String viewType) {
    final grouped = <String, List<Task>>{};
    for (final task in tasks) {
      final key = task.topicName ?? ViewPaneKeys.noTopic;
      grouped.putIfAbsent(key, () => []);
      grouped[key]!.add(task);
    }

    final keys = grouped.keys.toList()..sort((a, b) {
      if (a == ViewPaneKeys.automations) return -1;
      if (b == ViewPaneKeys.automations) return 1;
      if (a == ViewPaneKeys.noTopic) return 1;
      if (b == ViewPaneKeys.noTopic) return -1;
      return a.compareTo(b);
    });

    final s = widget.state.strings;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < keys.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.md),
          _TaskGroupPane(
            key: ValueKey('topic-${keys[i]}'),
            title: keys[i] == ViewPaneKeys.noTopic
                ? s['noTopic']
                : s.displayTopicName(keys[i]),
            tasks: sortTasksById(grouped[keys[i]]!),
            state: widget.state,
            viewType: viewType,
            displayMode: TaskViewDisplayMode.byTopic,
            topicKey: keys[i] == ViewPaneKeys.noTopic ? null : keys[i],
            accent: keys[i] == ViewPaneKeys.noTopic ||
                    keys[i] == ViewPaneKeys.automations
                ? null
                : widget.state.topicAccentForTask(grouped[keys[i]]!.first),
            isMain: keys[i] != ViewPaneKeys.noTopic &&
                keys[i] != ViewPaneKeys.automations &&
                widget.state.topicIsMain(grouped[keys[i]]!.first),
            topicTint: keys[i] != ViewPaneKeys.noTopic &&
                keys[i] != ViewPaneKeys.automations,
          ),
        ],
      ],
    );
  }
}

class _TaskGroupPane extends StatelessWidget {
  const _TaskGroupPane({
    super.key,
    required this.title,
    required this.tasks,
    required this.state,
    required this.viewType,
    required this.displayMode,
    this.sectionName,
    this.topicKey,
    this.accent,
    this.isMain = true,
    this.topicTint = false,
    this.isImportant = false,
    this.onToggleImportance,
  });

  final String title;
  final List<Task> tasks;
  final AppState state;
  final String viewType;
  final TaskViewDisplayMode displayMode;
  final String? sectionName;
  final String? topicKey;
  final Color? accent;
  final bool isMain;
  final bool topicTint;
  final bool isImportant;
  final VoidCallback? onToggleImportance;

  static const double _paneWidth = 280;
  static const double _minHeight = 200;

  static const _importantFlagColor = Color(0xFFC2410C);

  @override
  Widget build(BuildContext context) {
    final s = state.strings;
    return SizedBox(
      width: _paneWidth,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _minHeight),
        child: DecoratedBox(
          decoration: topicTint && accent != null
              ? AppColors.filePaneDecoration(
                  accent!,
                  'tasks',
                  isMainTopic: isMain,
                )
              : AppColors.noteDecoration(),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: AppSpacing.notePadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      if (onToggleImportance != null)
                        Tooltip(
                          message: isImportant
                              ? s['unmarkSectionImportant']
                              : s['markSectionImportant'],
                          child: InkWell(
                            onTap: onToggleImportance,
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.all(2),
                              child: AppIcon(
                                AppIcons.flag,
                                size: 14,
                                color: isImportant
                                    ? _importantFlagColor
                                    : AppColors.noteMeta.withValues(
                                        alpha: 0.45,
                                      ),
                              ),
                            ),
                          ),
                        ),
                      if (onToggleImportance != null)
                        const SizedBox(width: 6),
                      Expanded(
                        child: Text(title, style: AppTypography.noteTitleStyle),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ViewPaneTasksEditor(
                    viewType: viewType,
                    displayMode: displayMode,
                    sectionName: sectionName,
                    topicKey: topicKey,
                    tasks: tasks,
                    state: state,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionChip extends StatelessWidget {
  const _SectionChip({
    required this.section,
    required this.onToggleImportance,
    required this.onDelete,
  });

  final ViewSection section;
  final VoidCallback onToggleImportance;
  final VoidCallback onDelete;

  static const _importantFlagColor = Color(0xFFC2410C);

  @override
  Widget build(BuildContext context) {
    return InputChip(
      avatar: AppIcon(AppIcons.drag, size: 14, color: AppColors.textHint),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onToggleImportance,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsetsDirectional.only(end: 4),
              child: AppIcon(
                AppIcons.flag,
                size: 13,
                color: section.isImportant
                    ? _importantFlagColor
                    : AppColors.noteMeta.withValues(alpha: 0.45),
              ),
            ),
          ),
          Text(section.name, style: AppTypography.noteBodyStyle),
        ],
      ),
      deleteIcon: const AppIcon(AppIcons.close, size: 14),
      onDeleted: onDelete,
      visualDensity: VisualDensity.compact,
    );
  }
}
