import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../production_agent/agent_result_ui.dart';
import '../ui/adaptive_dialog.dart';
import '../ui/app_icons.dart';
import '../ui/app_switch.dart';
import '../ui/app_typography.dart';
import '../ui/app_segmented_toggle.dart';
import '../ui/confirm_dialog.dart';
import '../ui/dialog_field_style.dart';
import '../ui/dialog_metrics.dart';
import './automation.dart';
import './automation_builder_dialog.dart';
import './section_window_editor.dart';

enum _AutomationPage { regular, sectionWindows }

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
  var _page = _AutomationPage.regular;
  final _query = TextEditingController();

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() {}));
    state.loadAutomations();
    state.loadAiActions();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final saved = await showAutomationBuilderDialog(
      context: context,
      state: state,
    );
    if (saved && mounted) setState(() {});
  }

  Future<void> _edit(Automation automation) async {
    final saved = automation.isSectionWindow
        ? await showSectionWindowEditor(
            context: context,
            state: state,
            automation: automation,
          )
        : await showAutomationBuilderDialog(
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
      message: s.deleteAutomationMessage(
        state.automationDisplayName(automation),
      ),
      confirmLabel: s['delete'],
      cancelLabel: s['cancel'],
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await state.deleteAutomation(automation);
    if (mounted) setState(() {});
  }

  Future<void> _setEnabled(Automation automation, bool enabled) async {
    try {
      await state.updateAutomation(automation, {'enabled': enabled});
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _run(Automation automation) async {
    Navigator.pop(context);
    await presentAutomationRun(context, state, automation);
  }

  bool _matchesName(Automation item) {
    final q = _query.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    return state.automationDisplayName(item).toLowerCase().contains(q) ||
        item.name.toLowerCase().contains(q) ||
        item.nameHe.toLowerCase().contains(q);
  }

  List<Automation> get _visible {
    final source = _page == _AutomationPage.regular
        ? state.standardAutomations
        : state.sectionWindowAutomations;
    return [
      for (final item in source)
        if (_matchesName(item)) item,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final s = state.strings;
    final onRegular = _page == _AutomationPage.regular;
    final items = _visible;
    final emptyHint = _query.text.trim().isNotEmpty
        ? s['noMatchingAutomations']
        : (onRegular ? s['noAutomationsHint'] : s['noSectionWindowsHint']);

    return AppAdaptiveDialogShell(
      title: Text(onRegular ? s['automations'] : s['sectionWindows']),
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
          AppDialogChoiceField<_AutomationPage>(
            label: s['automationList'],
            options: [
              AppSegmentedOption(
                value: _AutomationPage.regular,
                label: s['automations'],
              ),
              AppSegmentedOption(
                value: _AutomationPage.sectionWindows,
                label: s['sectionWindows'],
              ),
            ],
            selected: _page,
            onSelected: (page) => setState(() {
              _page = page;
              _query.clear();
            }),
          ),
          const SizedBox(height: DialogFieldStyle.fieldGap),
          AppDialogField(
            label: s['searchByName'],
            child: TextField(
              controller: _query,
              decoration: DialogFieldStyle.decoration(
                hintText: s['searchByNameHint'],
              ),
            ),
          ),
          const SizedBox(height: DialogFieldStyle.fieldGap),
          SizedBox(
            height: 280,
            child: items.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      emptyHint,
                      textAlign: TextAlign.center,
                      style: AppTypography.metaStyle,
                    ),
                  )
                : ListView(
                    children: [
                      for (final item in items)
                        _row(item, allowDelete: onRegular),
                    ],
                  ),
          ),
          if (onRegular) ...[
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.icon(
                onPressed: _create,
                icon: const AppIcon(AppIcons.add, size: 16),
                label: Text(s['createAutomation']),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(Automation item, {required bool allowDelete}) {
    final s = state.strings;
    return ListTile(
      dense: true,
      onTap: () => _edit(item),
      title: Text(state.automationDisplayName(item)),
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
          if (!item.isSectionWindow)
            IconButton(
              tooltip: s['runNow'],
              icon: const AppIcon(AppIcons.runNow, size: 18),
              onPressed: () => _run(item),
            ),
          if (allowDelete)
            IconButton(
              tooltip: s['delete'],
              icon: const AppIcon(AppIcons.trash, size: 18),
              onPressed: () => _confirmDelete(item),
            ),
          AppSwitch(
            value: item.enabled,
            onChanged: (on) => _setEnabled(item, on),
          ),
        ],
      ),
    );
  }

  String _subtitle(Automation item) {
    final schedule = item.schedule ?? '';
    if (item.isSectionWindow) {
      final minutes = item.windowDurationMinutes;
      return [
        schedule,
        if (minutes != null) '${minutes}m',
      ].where((part) => part.isNotEmpty).join(' · ');
    }
    return [schedule, '${item.steps.length}'].join(' · ');
  }
}

/// Run an automation now and show what its steps did.
Future<void> presentAutomationRun(
  BuildContext context,
  AppState state,
  Automation automation,
) async {
  if (state.aiRunning) return;
  try {
    final result = await state.runAutomationNow(automation);
    if (state.aiCancelRequested) {
      await discardCancelledAutomationRun(state, result);
      return;
    }
    if (!context.mounted) return;
    await presentAutomationRunResult(context, state, result);
  } catch (e) {
    if (state.aiCancelRequested) {
      state.endAiRun();
      return;
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(e.toString())));
  }
}
