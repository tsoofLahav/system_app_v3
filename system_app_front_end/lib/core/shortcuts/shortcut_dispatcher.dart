import 'package:flutter/material.dart';

import '../app_state.dart';
import '../../features/create_topic/add_file_dialog.dart';
import '../../features/create_topic/create_topic_dialog.dart';
import '../../features/shell/ai_tool_bar.dart';
import 'shortcut_catalog.dart';

Future<void> dispatchShortcutAction(
  BuildContext context,
  AppState state,
  String actionId,
) async {
  switch (actionId) {
    case ShortcutActionIds.addTopic:
      final result = await showDialog<CreateTopicResult>(
        context: context,
        builder: (_) => CreateTopicDialog(state: state),
      );
      if (result == null || !context.mounted) return;
      await state.createTopic(
        name: result.name,
        type: result.type,
        icon: result.icon,
        color: result.color,
      );
      return;
    case ShortcutActionIds.addFile:
      final topic = state.selectedTopic;
      if (topic == null || !context.mounted) return;
      final fileResult = await showAddFileDialog(
        context: context,
        state: state,
        topic: topic,
      );
      if (fileResult == null) return;
      await state.addFile(
        topic: topic,
        name: fileResult.name,
        isEssence: fileResult.isEssence,
      );
      return;
    case ShortcutActionIds.aiConsult:
      await runAgentPrompt(context, state);
      return;
    default:
      return;
  }
}

String? shortcutTooltipSuffix(AppState state, String actionId) => null;
