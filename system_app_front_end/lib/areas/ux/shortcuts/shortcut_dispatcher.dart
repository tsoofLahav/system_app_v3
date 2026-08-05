import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../files/editor/document_editor_controller.dart';
import '../../objects/views/assign_task_view_dialog.dart';
import '../create_topic/add_file_dialog.dart';
import '../sidebar/sidebar_create_menu.dart';
import '../../production_agent/ai_tool_bar.dart';
import './shortcut_catalog.dart';

Future<void> dispatchShortcutAction(
  BuildContext context,
  AppState state,
  String actionId,
) async {
  switch (actionId) {
    case ShortcutActionIds.addTopic:
      await createTopicFromDialog(context, state);
      return;
    case ShortcutActionIds.addView:
      await createViewFromDialog(context, state);
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
