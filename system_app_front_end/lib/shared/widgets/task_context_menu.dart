import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/models/block.dart';
import '../../core/models/task.dart';
import '../../core/models/task_view_membership.dart';
import '../../core/models/task_view_menu_context.dart';
import '../../core/models/view_section.dart';
import '../../core/registry/task_view_display.dart';
import '../../core/registry/view_registry.dart';
import '../../features/blocks/block_context_menu.dart';
import '../../features/blocks/block_text_focus.dart';
import '../../features/blocks/format_range.dart';
import 'app_context_menu.dart';

/// Pick a topic before creating a task in a by-section view pane.
  Future<int?> showViewTopicPickerMenu({
  required BuildContext context,
  required Offset globalPosition,
  required AppState state,
}) async {
  AppContextMenu.dismissActive();
  final strings = state.strings;
  final entries = <AppContextMenuEntry>[
    for (final topic in state.activeTopics)
      AppContextMenuItem(
        value: 'topic:${topic.id}',
        label: state.topicDisplayName(topic),
      ),
  ];
  if (entries.isEmpty) return null;

  final value = await AppContextMenu.show(
    context: context,
    globalPosition: globalPosition,
    entries: entries,
    isRtl: strings.isRtl,
  );
  if (value == null || !value.startsWith('topic:')) return null;
  return int.tryParse(value.substring(6));
}

/// Unified task right-click menu: file/block actions, clipboard, view assignment.
Future<void> showTaskContextMenu({
  required BuildContext context,
  required Offset globalPosition,
  required Task task,
  required AppState state,
  VoidCallback? onCopy,
  VoidCallback? onCut,
  Future<void> Function()? onPaste,
  VoidCallback? onCopyAll,
  Future<void> Function()? onDelete,
  String? fileType,
  Block? targetBlock,
  BlockMenuHandler? onBlockAction,
  TaskViewMenuContext? viewMenuContext,
}) async {
  AppContextMenu.dismissActive();
  final strings = state.strings;
  final memberships = await state.membershipsForTask(task.id);
  final sectionsByView = viewMenuContext == null
      ? await _loadSectionsByView(state)
      : <String, List<ViewSection>>{};
  if (!context.mounted) return;

  final entries = <AppContextMenuEntry>[];

  if (BlockTextFocusRegistry.hasFocus) {
    entries.addAll(BlockContextMenu.buildTextEntries(strings));
  }

  if (fileType != null && onBlockAction != null) {
    if (entries.isNotEmpty) entries.add(const AppContextMenuDivider());
    entries.addAll(
      BlockContextMenu.buildFileEntries(
        strings: strings,
        fileType: fileType,
        targetBlock: targetBlock,
        includeTextActions: false,
      ),
    );
  }

  final taskEntries = <AppContextMenuEntry>[
    if (onDelete != null)
      AppContextMenuItem(value: 'delete_task', label: strings['delete']),
    if (onCut != null) AppContextMenuItem(value: 'cut', label: strings['cut']),
    if (onCopy != null) AppContextMenuItem(value: 'copy', label: strings['copy']),
    if (onPaste != null) AppContextMenuItem(value: 'paste', label: strings['paste']),
    if (onCopyAll != null)
      AppContextMenuItem(value: 'copy_all', label: strings['copyAllTasks']),
  ];

  final viewEntries = viewMenuContext != null
      ? _viewPaneAssignmentEntries(
          context: viewMenuContext,
          state: state,
          strings: strings,
          task: task,
          memberships: memberships,
        )
      : <AppContextMenuEntry>[
          for (final view in ViewRegistry.views)
            _viewSubmenu(
              viewType: view.type,
              viewLabel: state.viewLabel(view.type),
              strings: strings,
              memberships: memberships,
              sections: sectionsByView[view.type] ?? const [],
            ),
        ];

  if (entries.isNotEmpty &&
      (taskEntries.isNotEmpty || viewEntries.isNotEmpty)) {
    entries.add(const AppContextMenuDivider());
  }
  entries.addAll(taskEntries);

  if (taskEntries.isNotEmpty && viewEntries.isNotEmpty) {
    entries.add(const AppContextMenuDivider());
  }
  entries.addAll(viewEntries);

  final controller = BlockTextFocusRegistry.activeController;
  if (controller != null) {
    FormatRange.capturePending(controller.text, controller.selection);
  }
  BlockTextFocusRegistry.openMenuSession();
  String? value;
  try {
    value = await AppContextMenu.show(
      context: context,
      globalPosition: globalPosition,
      entries: entries,
      isRtl: strings.isRtl,
    );
  } finally {
    BlockTextFocusRegistry.closeMenuSession();
  }
  if (value == null) return;

  if (value.startsWith('text:')) {
    await BlockContextMenu.handleTextMenuValue(context, strings, value);
    return;
  }

  if (_isBlockAction(value)) {
    await onBlockAction?.call(value);
    return;
  }

  switch (value) {
    case 'cut':
      onCut?.call();
    case 'copy':
      onCopy?.call();
    case 'paste':
      await onPaste?.call();
    case 'copy_all':
      onCopyAll?.call();
    case 'delete_task':
      await onDelete?.call();
    default:
      if (value.startsWith('topic:')) {
        await _handleTopicAction(
          value: value,
          task: task,
          state: state,
          viewMenuContext: viewMenuContext,
        );
        return;
      }
      if (viewMenuContext != null && value.startsWith('view:')) {
        await _handleViewPaneSectionAction(
          value: value,
          task: task,
          state: state,
          viewMenuContext: viewMenuContext,
          memberships: memberships,
        );
        return;
      }
      await _handleViewAction(
        value: value,
        task: task,
        state: state,
        memberships: memberships,
      );
  }
}

List<AppContextMenuEntry> _viewPaneAssignmentEntries({
  required TaskViewMenuContext context,
  required AppState state,
  required AppStrings strings,
  required Task task,
  required List<TaskViewMembership> memberships,
}) {
  TaskViewMembership? membershipFor(String type) {
    for (final m in memberships) {
      if (m.viewType == type) return m;
    }
    return null;
  }

  final membership = membershipFor(context.viewType);

  if (context.displayMode == TaskViewDisplayMode.byTopic) {
    final sections = state.sectionsForViewType(context.viewType);
    if (sections.isEmpty) {
      return [
        AppContextMenuItem(
          value: membership != null
              ? 'view:${context.viewType}:remove'
              : 'view:${context.viewType}:toggle',
          label: membership != null
              ? strings['removeFromView']
              : strings['addToViewLabel'].replaceAll(
                  '{view}',
                  state.viewLabel(context.viewType),
                ),
        ),
      ];
    }

    final children = <AppContextMenuItem>[
      for (final section in sections)
        AppContextMenuItem(
          value: 'view:${context.viewType}:section:${section.name}',
          label: membership?.sectionName == section.name
              ? '${section.name} ✓'
              : section.name,
        ),
      if (membership != null)
        AppContextMenuItem(
          value: 'view:${context.viewType}:remove',
          label: strings['removeFromView'],
          destructive: true,
        ),
    ];
    return [
      AppContextMenuSubmenu(label: strings['sections'], children: children),
    ];
  }

  final topics = state.activeTopics;
  final children = <AppContextMenuItem>[
    for (final topic in topics)
      AppContextMenuItem(
        value: 'topic:${topic.id}',
        label: task.topicId == topic.id
            ? '${state.topicDisplayName(topic)} ✓'
            : state.topicDisplayName(topic),
      ),
  ];
  return [
    AppContextMenuSubmenu(label: strings['assignToTopic'], children: children),
  ];
}

Future<void> _handleTopicAction({
  required String value,
  required Task task,
  required AppState state,
  required TaskViewMenuContext? viewMenuContext,
}) async {
  if (viewMenuContext == null) return;
  final topicId = int.tryParse(value.substring(6));
  if (topicId == null) return;
  final topic = state.topicById(topicId);
  if (topic == null) return;
  if (task.topicId == topic.id) return;

  await state.assignTaskToTopicInView(
    task,
    topic,
    viewType: viewMenuContext.viewType,
    sectionName: viewMenuContext.sectionName,
  );
}

Future<void> _handleViewPaneSectionAction({
  required String value,
  required Task task,
  required AppState state,
  required TaskViewMenuContext viewMenuContext,
  required List<TaskViewMembership> memberships,
}) async {
  if (!value.startsWith('view:')) return;

  final parts = value.split(':');
  if (parts.length < 3) return;
  final viewType = parts[1];
  final action = parts[2];

  TaskViewMembership? membershipFor(String type) {
    for (final m in memberships) {
      if (m.viewType == type) return m;
    }
    return null;
  }

  final existing = membershipFor(viewType);

  if (action == 'toggle') {
    if (existing != null) {
      await state.removeTaskFromView(existing);
    } else {
      await state.addTaskToView(task, viewType);
    }
    return;
  }

  if (action == 'remove') {
    if (existing != null) {
      await state.removeTaskFromView(existing);
    }
    return;
  }

  if (action == 'section' && parts.length >= 4) {
    final sectionName = parts.sublist(3).join(':');
    await state.updateTaskViewSectionInView(
      task,
      viewType,
      sectionName: sectionName,
    );
  }
}

bool _isBlockAction(String value) =>
    value.startsWith('insert:') ||
    value == 'delete_block' ||
    value.startsWith('list:') ||
    value.startsWith('table:') ||
    value.startsWith('graph:') ||
    value.startsWith('image:');

Future<Map<String, List<ViewSection>>> _loadSectionsByView(
  AppState state,
) async {
  final sectionsByView = <String, List<ViewSection>>{};
  for (final view in ViewRegistry.views) {
    var sections = state.sectionsForViewType(view.type);
    if (sections.isEmpty) {
      try {
        sections = await state.loadSectionsForView(view.type);
      } catch (_) {
        sections = const [];
      }
    }
    sectionsByView[view.type] = sections;
  }
  return sectionsByView;
}

AppContextMenuSubmenu _viewSubmenu({
  required String viewType,
  required String viewLabel,
  required AppStrings strings,
  required List<TaskViewMembership> memberships,
  required List<ViewSection> sections,
}) {
  TaskViewMembership? membershipFor(String type) {
    for (final m in memberships) {
      if (m.viewType == type) return m;
    }
    return null;
  }

  final membership = membershipFor(viewType);
  final children = <AppContextMenuItem>[];

  if (sections.isEmpty) {
    children.add(
      AppContextMenuItem(
        value: 'view:$viewType:toggle',
        label: membership != null
            ? '${strings['assignedToView']} ✓'
            : strings['addToViewLabel'].replaceAll('{view}', viewLabel),
      ),
    );
  } else {
    for (final section in sections) {
      final selected = membership?.sectionName == section.name;
      children.add(
        AppContextMenuItem(
          value: 'view:$viewType:section:${section.name}',
          label: selected ? '${section.name} ✓' : section.name,
        ),
      );
    }
    if (membership != null) {
      children.add(
        AppContextMenuItem(
          value: 'view:$viewType:remove',
          label: strings['removeFromView'],
          destructive: true,
        ),
      );
    }
  }

  return AppContextMenuSubmenu(label: viewLabel, children: children);
}

Future<void> _handleViewAction({
  required String value,
  required Task task,
  required AppState state,
  required List<TaskViewMembership> memberships,
}) async {
  if (!value.startsWith('view:')) return;

  final parts = value.split(':');
  if (parts.length < 3) return;
  final viewType = parts[1];
  final action = parts[2];

  TaskViewMembership? membershipFor(String type) {
    for (final m in memberships) {
      if (m.viewType == type) return m;
    }
    return null;
  }

  final existing = membershipFor(viewType);

  if (action == 'toggle') {
    if (existing != null) {
      await state.assignTaskView(task, null);
    } else {
      await state.assignTaskView(task, viewType);
    }
    return;
  }

  if (action == 'remove') {
    await state.assignTaskView(task, null);
    return;
  }

  if (action == 'section' && parts.length >= 4) {
    final sectionName = parts.sublist(3).join(':');
    if (existing != null && existing.sectionName == sectionName) {
      await state.assignTaskView(task, null);
      return;
    }
    await state.assignTaskView(task, viewType, sectionName: sectionName);
  }
}

int lineIndexFromTextOffset(String text, int offset) {
  final clamped = offset.clamp(0, text.length);
  return '\n'.allMatches(text.substring(0, clamped)).length;
}
