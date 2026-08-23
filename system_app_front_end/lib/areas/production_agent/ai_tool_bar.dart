import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../automations/ai_actions_dialog.dart';
import '../ux/shortcuts/app_shortcuts.dart';
import '../ux/shortcuts/shortcut_catalog.dart';
import '../ui/action_icons.dart';
import '../ui/app_colors.dart';
import '../ui/app_icons.dart';
import './agent_prompt_dialog.dart';
import './agent_result_ui.dart';

const aiToolIconSize = 22.0;
const aiToolTapPadding = 4.0;

/// The AI section of the bottom bar.
///
/// The agent comes first — leading edge, so right in Hebrew and left in
/// English — because it is the one control that is always there. Then the
/// pinned actions in slot order, then ⋯ for the rest of them.
class AiToolBar extends StatelessWidget {
  const AiToolBar({
    super.key,
    required this.state,
    this.compact = false,
  });

  final AppState state;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final s = state.strings;
    final enabled = state.hasAiContext && !state.aiRunning;
    final pinned = state.barAiActions;

    return Row(
      mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
      children: [
        AiToolButton(
          tooltip: _tooltip(s['aiAgent'], ShortcutActionIds.aiConsult),
          icon: AppIcons.consult,
          enabled: enabled,
          onPressed: () => runAgentPrompt(context, state),
        ),
        for (final action in pinned)
          AiToolButton(
            tooltip: _tooltip(
              action.name,
              ShortcutActionIds.aiActionSlot(action.barSlot!),
            ),
            icon: actionIcon(action.icon),
            enabled: enabled,
            onPressed: () => runSavedAgentAction(context, state, action),
          ),
        AiToolButton(
          tooltip: s['manageAiActions'],
          icon: AppIcons.more,
          enabled: enabled,
          onPressed: () => showAiActionsDialog(context: context, state: state),
        ),
      ],
    );
  }

  String _tooltip(String label, String actionId) {
    final suffix = shortcutTooltipSuffix(state, actionId);
    return suffix == null ? label : '$label ($suffix)';
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
      icon: Icon(
        icon,
        size: aiToolIconSize,
        color: enabled ? AppColors.text : AppColors.textHint,
      ),
    );
  }
}
