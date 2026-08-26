import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../files/data/app_file.dart';
import '../../files/editor/document_editor_controller.dart';
import '../../files/editor/editor_key_handoff.dart';
import '../../files/editor/embeds/object_embed_widgets.dart';
import '../../files/rich_text/block_text_actions.dart';
import '../../files/rich_text/block_text_focus.dart';
import '../../objects/tasks/task_list_surface.dart';
import '../../objects/views/assign_task_view_dialog.dart';
import '../../objects/views/view_chrome_menu.dart';
import '../../../core/platform/app_form_factor.dart';
import '../arrange/file_arrange_overlay.dart';
import '../arrange/phone_file_reorder_sheet.dart';
import '../layout/file_layout_picker.dart';
import '../bring_file/bring_file_picker_dialog.dart';
import '../create_topic/add_file_dialog.dart';
import '../sidebar/sidebar_create_menu.dart';
import '../../production_agent/agent_prompt_dialog.dart';
import '../../production_agent/agent_result_ui.dart';
import './main_file_cycle.dart';
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
    if (!_contextAllows(state, ShortcutContextRequirement.aiContext)) return;
    final saved = state.aiActionInSlot(slot);
    if (saved == null) return;
    await runSavedAgentAction(context, state, saved);
    return;
  }

  if (action == null) return;
  if (!_contextAllows(state, action.context)) return;

  if (action.context == ShortcutContextRequirement.insertObject) {
    final insertType = action.insertType;
    if (insertType == null) return;
    final controller = DocumentEditorRegistry.active;
    if (controller == null) return;
    await controller.insertAtBlock(insertType);
    return;
  }

  if (action.context == ShortcutContextRequirement.textFocus) {
    await _dispatchTextAction(action);
    return;
  }

  switch (actionId) {
    case ShortcutActionIds.goHome:
      runAfterKeystroke(() {
        if (!context.mounted) return;
        state.goHome();
      });
      return;
    case ShortcutActionIds.bringFile:
      await showBringFilePicker(context: context, state: state);
      return;
    case ShortcutActionIds.openArrange:
      if (!context.mounted) return;
      if (isPhoneLayout) {
        await showPhoneFileReorderSheet(context: context, state: state);
      } else {
        await showFileArrangeOverlay(context, state);
      }
      return;
    case ShortcutActionIds.openFileLayout:
      if (!context.mounted || isPhoneLayout) return;
      await showFileLayoutPicker(context, state);
      return;
    case ShortcutActionIds.cycleMainFiles:
      await _cycleTopicFiles(context, state);
      return;
    case ShortcutActionIds.cycleMainFilesBack:
      await _cycleTopicFiles(context, state, reverse: true);
      return;
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
      final taskIds = TaskListSurfaceState.taskIdsForAssignView();
      if (taskIds.isEmpty || !context.mounted) return;
      await showAssignTaskViewDialog(
        context: context,
        state: state,
        taskIds: taskIds,
      );
      return;
    case ShortcutActionIds.aiConsult:
      await runAgentPrompt(context, state);
      return;
    case ShortcutActionIds.toggleLayoutMode:
      final next = state.viewDisplayMode == ViewDisplayMode.byTopic
          ? ViewDisplayMode.bySection
          : ViewDisplayMode.byTopic;
      runAfterKeystroke(() {
        if (!context.mounted) return;
        state.setViewDisplayMode(next);
      });
      return;
    case ShortcutActionIds.toggleLanguage:
      runAfterKeystroke(() {
        if (!context.mounted) return;
        state.toggleLanguage();
      });
      return;
    case ShortcutActionIds.addConnection:
      final info = InfoEmbedState.keyboardFocus;
      if (info != null) {
        await info.addConnectionFromShortcut();
        return;
      }
      await DocumentEditorRegistry.active?.insertAtBlock('bullet_list');
      return;
    case ShortcutActionIds.toggleReorderMode:
      final list = TaskListSurfaceState.keyboardFocus;
      if (list != null) {
        list.toggleReorderMode();
        return;
      }
      final viewChrome = ViewChromeRegistry.active;
      if (viewChrome != null) {
        viewChrome.onToggleTaskReorder();
        return;
      }
      state.toggleSidebarReorderMode();
      return;
    case ShortcutActionIds.toggleEmbedMoveMode:
      DocumentEditorRegistry.active?.toggleMoveMode?.call();
      return;
    default:
      return;
  }
}

bool shortcutHasTextFocus() {
  if (BlockTextFocusRegistry.hasFocus) return true;
  return DocumentEditorRegistry.active?.isFocused?.call() == true;
}

bool _contextAllows(AppState state, ShortcutContextRequirement requirement) {
  switch (requirement) {
    case ShortcutContextRequirement.none:
    case ShortcutContextRequirement.aiContext:
      return true;
    case ShortcutContextRequirement.topicMode:
      return _isTopicMode(state);
    case ShortcutContextRequirement.mainTopic:
      return _isTopicMode(state) && (state.selectedTopic?.isMain ?? false);
    case ShortcutContextRequirement.insertObject:
      return DocumentEditorRegistry.active != null;
    case ShortcutContextRequirement.textFocus:
      return shortcutHasTextFocus();
    case ShortcutContextRequirement.toggleLayoutMode:
      return state.isViewMode && state.selectedView != null;
  }
}

bool _isTopicMode(AppState state) {
  return !state.isViewMode &&
      !state.isArchiveMode &&
      !state.isDiagramMode &&
      state.selectedTopic != null;
}

Future<void> _dispatchTextAction(ShortcutAction action) async {
  final textAction = action.textAction;
  if (textAction == null) return;

  if (BlockTextFocusRegistry.hasFocus) {
    await runBlockTextAction(textAction);
    return;
  }

  await DocumentEditorRegistry.active?.applyTextAction?.call(textAction);
}

Future<void> _cycleTopicFiles(
  BuildContext context,
  AppState state, {
  bool reverse = false,
}) async {
  final topic = state.selectedTopic;
  if (topic == null || !_isTopicMode(state)) return;
  final files = state.selectedDetail?.files ?? const <AppFile>[];
  final next = cycledTopicFileOrder(
    ordered: state.orderedFilesFor(topic, files),
    reverse: reverse,
  );
  if (next == null) return;
  // Chrome, not a text action. Waiting for KeyUp (`runAfterKeystroke`) stalls
  // up to 500ms when no field is focused — Cmd stays "pressed" with no IME.
  await state.reorderTopicFiles(topic, ordered: next);
}
