import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../objects/tags/create_tag_dialog.dart';
import '../../objects/views/create_view_dialog.dart';
import '../../ui/adaptive_dialog.dart';
import '../create_topic/create_topic_dialog.dart';
import '../topic_types/topic_type_dialog.dart';
import '../widgets/app_context_menu.dart';

/// Bubble menu anchored at [globalPosition] (typically the sidebar `+`).
/// Each choice opens its own create dialog.
Future<void> showSidebarCreateMenu({
  required BuildContext context,
  required AppState state,
  required Offset globalPosition,
}) async {
  final s = state.strings;
  final choice = await AppContextMenu.show(
    context: context,
    globalPosition: globalPosition,
    isRtl: s.isRtl,
    width: AppContextMenu.compactMenuWidth,
    arrow: ContextMenuArrow.down,
    entries: [
      AppContextMenuItem(value: 'topic', label: s['topic']),
      AppContextMenuItem(value: 'topicType', label: s['topicType']),
      AppContextMenuItem(value: 'view', label: s['view']),
      AppContextMenuItem(value: 'tag', label: s['tag']),
    ],
  );
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case 'topic':
      await createTopicFromDialog(context, state);
    case 'topicType':
      await createTopicTypeFromDialog(context: context, state: state);
    case 'view':
      await createViewFromDialog(context, state);
    case 'tag':
      await createTagFromDialog(context, state);
  }
}

Future<void> createTopicFromDialog(BuildContext context, AppState state) async {
  final result = await showAppDialog<CreateTopicResult>(
    context: context,
    builder: (_) => CreateTopicDialog(state: state),
  );
  if (result == null) return;
  await state.createTopic(
    name: result.name,
    topicTypeId: result.topicTypeId,
    icon: result.icon,
    color: result.color,
  );
}

Future<void> createViewFromDialog(BuildContext context, AppState state) async {
  final name = await showCreateViewDialog(context: context, state: state);
  if (name == null) return;
  await state.createView(name: name);
}

Future<void> createTagFromDialog(BuildContext context, AppState state) async {
  final result = await showCreateTagDialog(context: context, state: state);
  if (result == null) return;
  await state.createWorkspaceTag(
    name: result.name,
    icon: result.icon,
    color: result.color,
  );
}
