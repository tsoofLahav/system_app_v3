import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../files/editor/document_editor_controller.dart';
import '../../objects/views/assign_task_view_dialog.dart';
import '../../objects/views/create_view_dialog.dart';
import '../create_topic/add_file_dialog.dart';
import '../create_topic/create_topic_dialog.dart';
import '../../production_agent/ai_tool_bar.dart';
import '../../ui/adaptive_dialog.dart';
import './shortcut_catalog.dart';

Future<void> dispatchShortcutAction(
  BuildContext context,
  AppState state,
  String actionId,
) async {
  switch (actionId) {
    case ShortcutActionIds.addTopic:
      final result = await showAppDialog<CreateTopicResult>(
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
    case ShortcutActionIds.addView:
      final name = await showCreateViewDialog(context: context, state: state);
      if (name == null || !context.mounted) return;
      await state.createView(name: name);
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
      await state.addFile(topic: topic, name: fileResult.name);
      return;
    case ShortcutActionIds.assignTaskView:
      final taskId = DocumentEditorRegistry.active?.focusedTaskId?.call();
      if (taskId == null || !context.mounted) return;
      await showAssignTaskViewDialog(
        context: context,
        state: state,
        taskId: taskId,
      );
      return;
    case ShortcutActionIds.aiConsult:
      await runAgentPrompt(context, state);
      return;
    default:
      return;
  }
}
