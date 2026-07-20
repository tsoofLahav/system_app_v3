import 'package:flutter/material.dart';

import '../../core/platform/app_form_factor.dart';
import '../../core/app_state.dart';
import '../../core/models/task.dart';
import '../../core/task_list_order.dart';
import '../../core/models/view_pane_sync_context.dart';
import '../../core/models/view_section.dart';
import '../../core/registry/task_view_display.dart';
import '../../design_system/adaptive_dialog.dart';
import '../../design_system/app_colors.dart';
import '../../design_system/app_icons.dart';
import '../../design_system/app_segmented_toggle.dart';
import '../../design_system/app_typography.dart';
import '../../design_system/note_widgets.dart';
import '../shell/app_bottom_bar.dart';
import '../../shared/widgets/main_pane_loader.dart';
import 'view_pane_tasks_editor.dart';

class TaskViewPane extends StatefulWidget {
  const TaskViewPane({super.key, required this.state});

  final AppState state;

  @override
  State<TaskViewPane> createState() => _TaskViewPaneState();
}

class _TaskViewPaneState extends State<TaskViewPane> {
  final _sectionController = TextEditingController();
  int? _shownResetAcknowledgementId;

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
    showAppDialog<void>(
      context: context,
      builder: (ctx) => AppAdaptiveDialogShell(
        title: Text(s.newSectionTitle(widget.state.viewLabel(viewType))),
        width: 400,
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

  void _maybeShowTaskResetAcknowledgement(String viewType) {
    final acknowledgement = widget.state.pendingTaskResetAcknowledgement;
    if (acknowledgement == null) return;
    if (acknowledgement.viewType != viewType) return;
    if (_shownResetAcknowledgementId == acknowledgement.id) return;
    _shownResetAcknowledgementId = acknowledgement.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showTaskResetAcknowledgementDialog(acknowledgement.id);
    });
  }

  Future<void> _showTaskResetAcknowledgementDialog(int acknowledgementId) async {
    final acknowledgement = widget.state.pendingTaskResetAcknowledgement;
    if (acknowledgement == null || acknowledgement.id != acknowledgementId) {
      return;
    }
    final s = widget.state.strings;
    final viewLabel = widget.state.viewLabel(acknowledgement.viewType);
    final missed = acknowledgement.missedTasks.take(8).toList();
    await showAppDialog<void>(
      context: context,
      builder: (ctx) => AppAdaptiveDialogShell(
        title: Text(s.taskResetAckTitle(viewLabel)),
        width: 400,
        actions: [
          TextButton(
            onPressed: () async {
              await widget.state.approveTaskResetAcknowledgement(
                acknowledgement.id,
              );
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text(s['ok']),
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.taskResetAckBody(
                resetCount: acknowledgement.resetCount,
                missedCount: acknowledgement.missedCount,
              ),
              style: AppTypography.noteBodyStyle,
              textAlign: TextAlign.start,
            ),
            if (missed.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                s['taskResetMissedTitle'],
                style: AppTypography.metaStyle,
                textAlign: TextAlign.start,
              ),
              const SizedBox(height: 6),
              for (final task in missed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '- ${task['title'] ?? ''}',
                    style: AppTypography.metaStyle,
                    textAlign: TextAlign.start,
                  ),
                ),
            ],
            const SizedBox(height: 8),
            Text(
              s['taskResetReportArchived'],
              style: AppTypography.metaStyle.copyWith(
                color: AppColors.textHint,
              ),
              textAlign: TextAlign.start,
            ),
          ],
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
      return MainPaneLoader(message: label);
    }

    _maybeShowTaskResetAcknowledgement(viewType);

    final phone = isPhoneLayout;
    final bottomInset = phone ? 56.0 : AppBottomBarMetrics.scrollInset;

    return TopicCanvasBackground(
      accent: AppColors.text,
      isMain: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: phone
                ? const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 8)
                : const EdgeInsetsDirectional.fromSTEB(24, 20, 24, 12),
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
                    AppSegmentedToggle<TaskViewDisplayMode>(
                      options: [
                        AppSegmentedOption(
                          value: TaskViewDisplayMode.bySection,
                          label: s['bySection'],
                        ),
                        AppSegmentedOption(
                          value: TaskViewDisplayMode.byTopic,
                          label: s['byTopic'],
                        ),
                      ],
                      selected: displayMode,
                      onSelected: widget.state.setViewDisplayMode,
                    ),
                    if (displayMode == TaskViewDisplayMode.bySection) ...[
                      const SizedBox(width: 8),
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
                  phone
                      ? Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final section in sections)
                              _SectionChip(
                                section: section,
                                onToggleImportance: () =>
                                    widget.state.setViewSectionImportance(
                                  section,
                                  important: !section.isImportant,
                                ),
                                onDelete: () =>
                                    widget.state.deleteViewSection(section),
                              ),
                          ],
                        )
                      : SizedBox(
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
                                  padding:
                                      const EdgeInsetsDirectional.only(end: 6),
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
                    scrollDirection:
                        phone ? Axis.vertical : Axis.horizontal,
                    padding: AppSpacing.canvasPadding.copyWith(
                      left: phone ? 12 : AppSpacing.canvasPadding.left,
                      right: phone ? 12 : AppSpacing.canvasPadding.right,
                      bottom: AppSpacing.canvasPadding.bottom + bottomInset,
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

    final firstSectionName = sections.isNotEmpty ? sections.first.name : null;

    for (final task in tasks) {
      var key = task.sectionName;
      if (key == null ||
          key.isEmpty ||
          (sections.isNotEmpty && !sections.any((s) => s.name == key))) {
        key = firstSectionName ?? _uncategorizedKey;
      }
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

    if (isPhoneLayout) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < panes.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.md),
            panes[i],
          ],
        ],
      );
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

    Widget paneForKey(String key) {
      return _TaskGroupPane(
        key: ValueKey('topic-$key'),
        title: key == ViewPaneKeys.noTopic
            ? s['noTopic']
            : s.displayTopicName(key),
        tasks: sortTasksById(grouped[key]!),
        state: widget.state,
        viewType: viewType,
        displayMode: TaskViewDisplayMode.byTopic,
        topicKey: key == ViewPaneKeys.noTopic ? null : key,
        accent: key == ViewPaneKeys.noTopic || key == ViewPaneKeys.automations
            ? null
            : widget.state.topicAccentForTask(grouped[key]!.first),
        isMain: key != ViewPaneKeys.noTopic &&
            key != ViewPaneKeys.automations &&
            widget.state.topicIsMain(grouped[key]!.first),
        topicTint:
            key != ViewPaneKeys.noTopic && key != ViewPaneKeys.automations,
      );
    }

    if (isPhoneLayout) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < keys.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.md),
            paneForKey(keys[i]),
          ],
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < keys.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.md),
          paneForKey(keys[i]),
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
    final paneBody = ConstrainedBox(
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
                    if (onToggleImportance != null) const SizedBox(width: 6),
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
    );

    if (isPhoneLayout) {
      return paneBody;
    }

    return SizedBox(
      width: _paneWidth,
      child: paneBody,
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
