import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/shortcuts/app_shortcuts.dart';
import '../../core/shortcuts/shortcut_catalog.dart';
import '../../design_system/app_colors.dart';
import '../../design_system/app_icons.dart';
import '../../design_system/app_typography.dart';
import '../../design_system/glass_surface.dart';
import '../../shared/change_review/text_diff_dialog.dart';

const aiToolIconSize = 22.0;
const aiToolTapPadding = 4.0;

Future<void> runAgentPrompt(BuildContext context, AppState state) async {
  final s = state.strings;
  if (!state.hasAiContext || state.aiRunning) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s['aiNoContext'] ?? 'No context')),
    );
    return;
  }

  final controller = TextEditingController();
  final prompt = await showDialog<String>(
    context: context,
    builder: (ctx) => AppGlassDialog(
      title: Text(s['aiAgent'] ?? 'Agent'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s['cancel'])),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text.trim()),
          child: Text(s['run'] ?? 'Run'),
        ),
      ],
      child: TextField(
        controller: controller,
        autofocus: true,
        maxLines: 4,
        decoration: InputDecoration(
          hintText: s['aiAgentPromptHint'] ?? 'What should the agent do?',
        ),
      ),
    ),
  );
  if (prompt == null || prompt.isEmpty || !context.mounted) return;

  try {
    final result = await state.runAgentPrompt(prompt, applyMode: 'review');
    if (!context.mounted || result == null) return;
    final changes = result['proposed_changes'] as List?;
    if (changes != null && changes.isNotEmpty) {
      final first = changes.first as Map;
      final review = first['review'] as Map?;
      final diff = review?['diff_hunks']?.toString() ?? '';
      final apply = await TextDiffDialog.show(
        context,
        title: s['reviewChanges'] ?? 'Review changes',
        diffHunks: diff,
      );
      if (apply == true) {
        await state.applyAgentReview();
      } else {
        state.dismissAgentReview();
      }
    }
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.toString())),
    );
  }
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
    final enabled = state.hasAiContext && !state.aiRunning;

    return Row(
      mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
      children: [
        AiToolButton(
          tooltip: _tooltip(state, s['aiAgent'] ?? 'Agent', ShortcutActionIds.aiConsult),
          icon: AppIcons.consult,
          enabled: enabled,
          onPressed: () => runAgentPrompt(context, state),
        ),
      ],
    );
  }

  String _tooltip(AppState state, String label, String actionId) => label;
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
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(aiToolTapPadding),
          child: Icon(
            icon,
            size: aiToolIconSize,
            color: enabled ? AppColors.text : AppColors.textHint,
          ),
        ),
      ),
    );
  }
}
