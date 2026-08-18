import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../production_agent/agent_result_ui.dart';
import '../ui/adaptive_dialog.dart';
import '../ui/app_icons.dart';
import '../ui/app_typography.dart';
import '../ui/confirm_dialog.dart';
import '../ui/dialog_metrics.dart';
import './automation.dart';
import './automation_builder_dialog.dart';

Future<void> showAutomationDialog({
  required BuildContext context,
  required AppState state,
}) async {
  await showAppDialog<void>(
    context: context,
    builder: (ctx) => _AutomationDialog(state: state),
  );
}

class _AutomationDialog extends StatefulWidget {
  const _AutomationDialog({required this.state});

  final AppState state;

  @override
  State<_AutomationDialog> createState() => _AutomationDialogState();
}

class _AutomationDialogState extends State<_AutomationDialog> {
  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    state.loadAutomations();
    state.loadAiActions();
  }

  Future<void> _create() async {
    final saved = await showAutomationBuilderDialog(
      context: context,
      state: state,
    );
    if (saved && mounted) setState(() {});
  }

  Future<void> _edit(Automation automation) async {
    final saved = await showAutomationBuilderDialog(
      context: context,
      state: state,
      automation: automation,
    );
    if (saved && mounted) setState(() {});
  }

  Future<void> _confirmDelete(Automation automation) async {
    final s = state.strings;
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: s['delete'],
      message: s.deleteAutomationMessage(automation.name),
      confirmLabel: s['delete'],
      cancelLabel: s['cancel'],
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await state.deleteAutomation(automation);
    if (mounted) setState(() {});
  }

  Future<void> _run(Automation automation) async {
    Navigator.pop(context);
    await presentAutomationRun(context, state, automation);
  }

  @override
  Widget build(BuildContext context) {
    final s = state.strings;
    final items = state.automations;

    return AppAdaptiveDialogShell(
      title: Text(s['automations']),
      width: AppDialogMetrics.wideWidth,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s['close']),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.icon(
              onPressed: _create,
              icon: const AppIcon(AppIcons.add, size: 16),
              label: Text(s['createAutomation']),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 280,
            child: items.isEmpty
                ? Center(
                    child: Text(
                      s['noAutomationsHint'],
                      textAlign: TextAlign.center,
                      style: AppTypography.metaStyle,
                    ),
                  )
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return ListTile(
                        dense: true,
                        onTap: () => _edit(item),
                        title: Text(item.name),
                        subtitle: Text(
                          _subtitle(item),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: s['edit'],
                              icon: const AppIcon(AppIcons.edit, size: 18),
                              onPressed: () => _edit(item),
                            ),
                            IconButton(
                              tooltip: s['runNow'],
                              icon: const AppIcon(AppIcons.runNow, size: 18),
                              onPressed: () => _run(item),
                            ),
                            IconButton(
                              tooltip: s['delete'],
                              icon: const AppIcon(AppIcons.trash, size: 18),
                              onPressed: () => _confirmDelete(item),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _subtitle(Automation item) {
    final schedule = item.schedule ?? '';
    final n = item.steps.length;
    final off = item.enabled ? '' : state.strings['disabled'];
    return [schedule, '$n', if (off.isNotEmpty) off].join(' · ');
  }
}

/// Run an automation now and show what its steps did.
Future<void> presentAutomationRun(
  BuildContext context,
  AppState state,
  Automation automation,
) async {
  try {
    final result = await state.runAutomationNow(automation);
    if (!context.mounted) return;
    await presentAutomationRunResult(context, state, result);
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.toString())),
    );
  }
}
