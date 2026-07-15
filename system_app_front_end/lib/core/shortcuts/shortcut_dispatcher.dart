import 'package:flutter/material.dart';

import '../../design_system/app_typography.dart';
import '../../design_system/glass_surface.dart';
import '../../features/arrange/file_arrange_overlay.dart';
import '../../features/blocks/block_text_actions.dart';
import '../../features/blocks/block_text_focus.dart';
import '../../features/bring_file/bring_file_picker_dialog.dart';
import '../../features/create_topic/add_file_dialog.dart';
import '../../features/create_topic/create_topic_dialog.dart';
import '../app_state.dart';
import '../models/app_file.dart';
import '../registry/file_behavior_registry.dart';
import '../services/ai_service.dart';
import 'shortcut_catalog.dart';

class ShortcutDispatcher {
  const ShortcutDispatcher._();

  static bool canInvoke(AppState state, String actionId) {
    final action = shortcutActionById(actionId);
    if (action == null) return false;
    if (state.aiRunning && action.aiTool != null) return false;

    switch (action.context) {
      case ShortcutContextRequirement.none:
        return true;
      case ShortcutContextRequirement.topicMode:
        return !state.isArchiveMode &&
            !state.isViewMode &&
            state.selectedDetail != null;
      case ShortcutContextRequirement.mainTopic:
        return !state.isArchiveMode &&
            !state.isViewMode &&
            state.selectedDetail != null &&
            state.selectedTopic?.isMain == true;
      case ShortcutContextRequirement.aiContext:
        if (action.aiTool == 'move_file_to_topic') {
          return state.canRunAiTool(action.aiTool!);
        }
        return state.canRunAiTool(action.aiTool ?? '');
      case ShortcutContextRequirement.textFocus:
        return BlockTextFocusRegistry.hasFocus;
      case ShortcutContextRequirement.insertBlock:
        return _insertTargetFile(state) != null &&
            _blockAllowed(state, action.blockType);
    }
  }

  static Future<void> invoke(
    BuildContext context,
    AppState state,
    String actionId,
  ) async {
    if (!canInvoke(state, actionId)) return;
    final action = shortcutActionById(actionId);
    if (action == null) return;

    switch (actionId) {
      case ShortcutActionIds.goHome:
        state.goHome();
        return;
      case ShortcutActionIds.bringFile:
        final entry = await showBringFilePickerDialog(context, state);
        if (entry == null || !context.mounted) return;
        await state.bringFile(entry.topic, entry.file);
        return;
      case ShortcutActionIds.openArrange:
        await showFileArrangeOverlay(context, state);
        return;
      case ShortcutActionIds.cycleMainFiles:
        await state.cycleMainFilesForward();
        return;
      case ShortcutActionIds.addFile:
        final topic = state.selectedTopic;
        final detail = state.selectedDetail;
        if (topic == null || detail == null) return;
        final result = await showDialog<AddFileResult>(
          context: context,
          builder: (_) => AddFileDialog(
            state: state,
            topic: topic,
            existingTypes:
                detail.files.map((f) => f.type).toList(growable: false),
          ),
        );
        if (result == null || !context.mounted) return;
        await state.addFile(
          topic: topic,
          type: result.type,
          name: result.name,
        );
        return;
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
          selectedFileTypes: result.selectedFileTypes,
        );
        return;
    }

    if (!context.mounted) return;

    if (action.aiTool != null) {
      await _runAiTool(context, state, action.aiTool!);
      return;
    }

    if (action.textAction != null) {
      await runBlockTextAction(action.textAction!);
      return;
    }

    if (action.blockType != null) {
      await _insertBlock(state, action.blockType!);
    }
  }

  static Future<void> _runAiTool(
    BuildContext context,
    AppState state,
    String tool,
  ) async {
    final s = state.strings;
    if (tool == 'move_file_to_topic') {
      if (!state.canRunAiTool(tool)) {
        _snack(context, s['aiNoFileFocus']);
        return;
      }
      final file = state.aiFocusedFile;
      final topic = state.selectedTopic;
      if (file == null || topic == null) return;
      try {
        final result = await state.runAiMoveFile(topic, file);
        if (!context.mounted || result == null) return;
        _showAiResult(context, state, result);
      } catch (e) {
        if (!context.mounted) return;
        _snack(context, e.toString());
      }
      return;
    }

    if (!state.canRunAiTool(tool)) {
      _snack(context, s['aiNoContext']);
      return;
    }

    try {
      final result = await state.runAiTool(tool);
      if (!context.mounted || result == null) return;
      _showAiResult(context, state, result);
    } catch (e) {
      if (!context.mounted) return;
      _snack(context, e.toString());
    }
  }

  static void _showAiResult(
    BuildContext context,
    AppState state,
    AiRunResult result,
  ) {
    final s = state.strings;
    final message = result.result ?? s['aiDone'];
    final topic = result.targetTopicName;
    final file = result.targetFileName;
    final target = topic != null && file != null
        ? '$topic → $file'
        : (file ?? topic);
    final title = result.status == 'not_graphable' ? s['aiGraph'] : s['aiDone'];

    showDialog<void>(
      context: context,
      builder: (ctx) => AppGlassDialog(
        title: Text(title),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s['ok'])),
        ],
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (target != null) ...[
                Text(target, style: AppTypography.metaStyle),
                const SizedBox(height: 8),
              ],
              Text(message, style: AppTypography.noteBodyStyle),
            ],
          ),
        ),
      ),
    );
  }

  static void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  static AppFile? _insertTargetFile(AppState state) {
    final detail = state.selectedDetail;
    final topic = state.selectedTopic;
    if (detail == null || topic == null) return null;
    final focused = state.aiFocusedFile;
    if (focused != null && !state.isGuestFile(focused)) return focused;
    final main = state.mainFilesFor(topic, detail.files);
    if (main.isEmpty) return null;
    return main.first;
  }

  static bool _blockAllowed(AppState state, String? blockType) {
    if (blockType == null) return false;
    final file = _insertTargetFile(state);
    if (file == null) return false;
    final allowed = FileBehaviorRegistry.contextMenuForFileType(file.type);
    return allowed.contains(blockType);
  }

  static Future<void> _insertBlock(AppState state, String blockType) async {
    final file = _insertTargetFile(state);
    if (file == null) return;
    final blocks = state.selectedDetail?.blocksByFileId[file.id] ?? [];
    await state.insertDefaultBlock(
      file,
      blockType,
      orderIndex: blocks.length,
    );
  }
}
