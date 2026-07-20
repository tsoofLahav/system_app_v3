import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../features/blocks/text_emoji_picker.dart';
import '../../core/shortcuts/app_shortcuts.dart';
import '../../core/shortcuts/shortcut_catalog.dart';
import '../../core/services/ai_service.dart';
import '../../design_system/app_colors.dart';
import '../../design_system/app_icons.dart';
import '../../design_system/app_typography.dart';
import '../../design_system/glass_surface.dart';

const aiToolIconSize = 22.0;
const aiToolTapPadding = 4.0;

Future<void> runAiTool(
  BuildContext context,
  AppState state,
  String tool,
) async {
  final s = state.strings;
  if (tool == 'move_file_to_topic') {
    if (!state.canRunAiTool(tool)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s['aiNoFileFocus'])));
      return;
    }
    final file = state.aiFocusedFile;
    final topic = state.selectedTopic;
    if (file == null || topic == null) return;
    try {
      final result = await state.runAiMoveFile(topic, file);
      if (!context.mounted || result == null) return;
      showAiToolResult(context, state, result);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
    return;
  }

  if (tool == 'suggest_emoji') {
    await runSuggestEmoji(context, state);
    return;
  }

  if (!state.canRunAiTool(tool)) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(s['aiNoContext'])));
    return;
  }

  if (tool == 'review') {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(s['aiReviewSoon'])));
    return;
  }

  try {
    final result = await state.runAiTool(tool);
    if (!context.mounted || result == null) return;
    showAiToolResult(context, state, result);
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(e.toString())));
  }
}

void showAiToolResult(
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

class AiToolBar extends StatelessWidget {
  const AiToolBar({
    super.key,
    required this.state,
    required this.onTool,
    this.compact = false,
  });

  final AppState state;
  final ValueChanged<String> onTool;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final s = state.strings;
    final hasContext = state.hasAiContext;
    final running = state.aiRunning;
    final enabled = hasContext && !running;
    final graphEnabled = hasContext && !running;
    final moveFileEnabled =
        state.canRunAiTool('move_file_to_topic') && !running;
    final suggestEmojiEnabled =
        state.canRunAiTool('suggest_emoji') && !running;

    final tools = Row(
      mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
      children: [
        AiToolButton(
          tooltip: _tooltip(state, s['aiConsult'], ShortcutActionIds.aiConsult),
          icon: AppIcons.consult,
          enabled: enabled,
          onPressed: () => onTool('consult'),
        ),
        AiToolButton(
          tooltip: _tooltip(
            state,
            s['aiSummarize'],
            ShortcutActionIds.aiSummarize,
          ),
          icon: AppIcons.summarize,
          enabled: enabled,
          onPressed: () => onTool('summarize_to_doc'),
        ),
        AiToolButton(
          tooltip: _tooltip(
            state,
            s['aiSmartList'],
            ShortcutActionIds.aiSmartList,
          ),
          icon: AppIcons.smartList,
          enabled: enabled,
          onPressed: () => onTool('smart_list'),
        ),
        AiToolButton(
          tooltip: _tooltip(state, s['aiImage'], ShortcutActionIds.aiImage),
          icon: AppIcons.image,
          enabled: enabled,
          onPressed: () => onTool('create_image'),
        ),
        AiToolButton(
          tooltip: _tooltip(state, s['aiGraph'], ShortcutActionIds.aiGraph),
          icon: AppIcons.graph,
          enabled: graphEnabled,
          onPressed: () => onTool('create_graph'),
        ),
        AiToolButton(
          tooltip: _tooltip(
            state,
            s['aiSuggestEmoji'],
            ShortcutActionIds.aiSuggestEmoji,
          ),
          icon: AppIcons.ai,
          enabled: suggestEmojiEnabled,
          onPressed: () => onTool('suggest_emoji'),
        ),
        AiToolButton(
          tooltip: _tooltip(
            state,
            s['aiMoveFile'],
            ShortcutActionIds.aiMoveFile,
          ),
          icon: AppIcons.moveFileAi,
          enabled: moveFileEnabled,
          onPressed: () => onTool('move_file_to_topic'),
        ),
        AiToolButton(
          tooltip: s['aiReview'],
          icon: AppIcons.review,
          enabled: !running,
          onPressed: () => onTool('review'),
        ),
      ],
    );

    if (compact) return tools;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: tools,
    );
  }

  static String _tooltip(AppState state, String label, String actionId) {
    final suffix = shortcutTooltipSuffix(state, actionId);
    if (suffix == null) return label;
    return '$label ($suffix)';
  }
}

class AiToolButton extends StatelessWidget {
  const AiToolButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      padding: const EdgeInsets.all(aiToolTapPadding),
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      onPressed: enabled ? onPressed : null,
      icon: AppIcon(
        icon,
        size: aiToolIconSize,
        enabled: enabled,
        color: enabled
            ? AppColors.text.withValues(alpha: 0.78)
            : AppColors.textHint.withValues(alpha: 0.32),
      ),
    );
  }
}
