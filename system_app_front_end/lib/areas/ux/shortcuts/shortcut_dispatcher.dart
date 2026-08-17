import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../files/editor/document_editor_controller.dart';
import '../../objects/views/assign_task_view_dialog.dart';
import '../create_topic/add_file_dialog.dart';
import '../sidebar/sidebar_create_menu.dart';
import '../../production_agent/agent_prompt_dialog.dart';
import '../../production_agent/agent_result_ui.dart';
import './shortcut_catalog.dart';

Future<void> dispatchShortcutAction(
  BuildContext context,
  AppState state,
  String actionId,
) async {
  final action = shortcutActionById(actionId);

  // A slot key fires whatever action sits in that seat on the AI bar, and does
  // nothing while the seat is empty.
  final slot = ShortcutActionIds.slotOfAiAction(actionId);
  if (slot != null) {
    final saved = state.aiActionInSlot(slot);
    if (saved == null) return;
    await runSavedAgentAction(context, state, saved);
    return;
  }

  if (action?.context == ShortcutContextRequirement.insertObject) {
    final insertType = action!.insertType;
    if (insertType == null) return;
    final controller = DocumentEditorRegistry.active;
    if (controller == null) return;
    await controller.insertAtBlock(insertType);
    return;
  }

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
