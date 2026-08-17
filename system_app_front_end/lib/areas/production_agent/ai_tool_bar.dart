import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../automations/automation.dart';
import '../automations/automation_dialog.dart';
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
/// Saved actions the user pinned come first, in slot order, then the menu of
/// every action, then the agent — which never moves, so the one thing that is
/// always there is always in the same place.
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
    final all = state.manualAiActions;

    return Row(
      mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
      children: [
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
        if (all.isNotEmpty)
          PopupMenuButton<Automation?>(
            enabled: enabled,
            tooltip: s['aiActions'],
            icon: Icon(
              Icons.bolt_outlined,
              size: aiToolIconSize,
              color: enabled ? AppColors.text : AppColors.textHint,
            ),
            itemBuilder: (ctx) => [
              for (final action in all)
                PopupMenuItem(
                  value: action,
                  child: Row(
                    children: [
                      AppIcon(actionIcon(action.icon), size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          action.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              const PopupMenuDivider(),
              PopupMenuItem(value: null, child: Text(s['manageAiActions'])),
            ],
            onSelected: (action) => action == null
                ? showAutomationDialog(context: context, state: state)
                : runSavedAgentAction(context, state, action),
          ),
        AiToolButton(
          tooltip: _tooltip(s['aiAgent'], ShortcutActionIds.aiConsult),
          icon: AppIcons.consult,
          enabled: enabled,
          onPressed: () => runAgentPrompt(context, state),
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
