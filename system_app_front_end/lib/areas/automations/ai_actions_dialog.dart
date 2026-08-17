import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../production_agent/agent_result_ui.dart';
import '../ui/action_icons.dart';
import '../ui/adaptive_dialog.dart';
import '../ui/app_colors.dart';
import '../ui/app_icons.dart';
import '../ui/app_typography.dart';
import '../ui/confirm_dialog.dart';
import '../ui/dialog_metrics.dart';
import './automation.dart';
import './automation_edit_dialog.dart';

/// The saved AI actions, and nothing else.
///
/// Opened from the ⋯ beside the AI bar. It only shows what already exists:
/// an action is born in the agent dialog, and scheduled automations live in
/// the automations dialog.
Future<void> showAiActionsDialog({
  required BuildContext context,
  required AppState state,
}) async {
  await showAppDialog<void>(
    context: context,
    builder: (ctx) => _AiActionsDialog(state: state),
  );
}

class _AiActionsDialog extends StatefulWidget {
  const _AiActionsDialog({required this.state});

  final AppState state;

  @override
  State<_AiActionsDialog> createState() => _AiActionsDialogState();
}

class _AiActionsDialogState extends State<_AiActionsDialog> {
  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    state.loadAutomations();
  }

  Future<void> _edit(Automation action) async {
    final saved = await showAutomationEditDialog(
      context: context,
      state: state,
      automation: action,
    );
    if (saved && mounted) setState(() {});
  }

  Future<void> _togglePin(Automation action) async {
    if (!action.isOnBar && state.firstFreeAiBarSlot == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(state.strings['aiBarFull'])),
      );
      return;
    }
    await state.setAiActionSlot(
      action,
      slot: action.isOnBar ? null : state.firstFreeAiBarSlot,
    );
    if (mounted) setState(() {});
  }

  Future<void> _delete(Automation action) async {
    final s = state.strings;
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: s['delete'],
      message: s.deleteActionMessage(action.name),
      confirmLabel: s['delete'],
      cancelLabel: s['cancel'],
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await state.deleteAutomation(action);
    if (mounted) setState(() {});
  }

  Future<void> _run(Automation action) async {
    Navigator.pop(context);
    await runSavedAgentAction(context, state, action);
  }

  @override
  Widget build(BuildContext context) {
    final s = state.strings;
    final actions = state.manualAiActions;

    return AppAdaptiveDialogShell(
      title: Text(s['aiActions']),
      width: AppDialogMetrics.wideWidth,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s['close']),
        ),
      ],
      child: SizedBox(
        height: 260,
        child: actions.isEmpty
            ? Center(
                child: Text(
                  s['noAiActionsHint'],
                  textAlign: TextAlign.center,
                  style: AppTypography.metaStyle,
                ),
              )
            : ListView.separated(
                itemCount: actions.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final action = actions[index];
                  return ListTile(
                    dense: true,
                    onTap: () => _edit(action),
                    leading: AppIcon(actionIcon(action.icon), size: 18),
                    title: Text(action.name),
                    subtitle: Text(
                      action.prompt,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (action.isOnBar)
                          Padding(
                            padding: const EdgeInsetsDirectional.only(end: 4),
                            child: Text(
                              '${action.barSlot}',
                              style: AppTypography.metaStyle.copyWith(
                                color: AppColors.text.withValues(alpha: 0.5),
                              ),
                            ),
                          ),
                        IconButton(
                          tooltip: action.isOnBar
                              ? s['takeOffBar']
                              : s['putOnBar'],
                          icon: AppIcon(
                            action.isOnBar
                                ? AppIcons.unpinFromBar
                                : AppIcons.pinToBar,
                            size: 18,
                          ),
                          onPressed: () => _togglePin(action),
                        ),
                        IconButton(
                          tooltip: s['edit'],
                          icon: const AppIcon(AppIcons.edit, size: 18),
                          onPressed: () => _edit(action),
                        ),
                        IconButton(
                          tooltip: s['runNow'],
                          icon: const AppIcon(AppIcons.runNow, size: 18),
                          onPressed: () => _run(action),
                        ),
                        IconButton(
                          tooltip: s['delete'],
                          icon: const AppIcon(AppIcons.trash, size: 18),
                          onPressed: () => _delete(action),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}
