import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/app_state.dart';
import './automation.dart';
import '../ui/action_icon_picker.dart';
import '../ui/action_icons.dart';
import '../ui/adaptive_dialog.dart';
import '../ui/app_icons.dart';
import '../ui/app_segmented_toggle.dart';
import '../ui/dialog_field_style.dart';
import '../ui/dialog_metrics.dart';
import '../production_agent/agent_result_ui.dart';
import '../production_agent/agent_run_defaults.dart';

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

class _AutomationDialogState extends State<_AutomationDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  var _creating = false;
  var _kind = _AutomationKind.manual;

  final _nameController = TextEditingController();
  final _promptController = TextEditingController();
  final _scheduleController = TextEditingController(text: '0 8 * * *');
  var _applyMode = defaultAutomationApplyMode;
  var _iconKey = defaultActionIconKey;
  var _onBar = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    widget.state.loadAutomations();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _nameController.dispose();
    _promptController.dispose();
    _scheduleController.dispose();
    super.dispose();
  }

  AppState get state => widget.state;

  bool get _barIsFull => state.firstFreeAiBarSlot == null;

  /// Puts an action on the bar or takes it off, from its row in the list.
  Future<void> _togglePin(Automation action) async {
    if (!action.isOnBar && _barIsFull) {
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

  Future<void> _create() async {
    final name = _nameController.text.trim();
    final prompt = _promptController.text.trim();
    if (name.isEmpty || prompt.isEmpty) return;

    final isScheduled = _kind == _AutomationKind.scheduled;
    setState(() => _creating = true);
    try {
      await state.createAutomation(
        name: name,
        prompt: prompt,
        applyMode: _applyMode,
        isScheduled: isScheduled,
        schedule: isScheduled ? _scheduleController.text.trim() : null,
        icon: _iconKey,
        // Only an action goes on the bar, and only if there is room.
        barSlot: !isScheduled && _onBar ? state.firstFreeAiBarSlot : null,
      );
      if (!mounted) return;
      _nameController.clear();
      _promptController.clear();
      setState(() {
        _creating = false;
        _onBar = false;
        _iconKey = defaultActionIconKey;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(state.strings['created'])),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _creating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _runAutomation(Automation automation) async {
    try {
      await runSavedAgentAction(context, state, automation);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = state.strings;
    final manual = state.manualAiActions;
    final scheduled = state.scheduledAutomations;

    return AppAdaptiveDialogShell(
      title: Text(s['automations']),
      width: AppDialogMetrics.wideWidth,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(s['close'])),
      ],
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TabBar(
              controller: _tabs,
              tabs: [
                Tab(text: s['aiActions']),
                Tab(text: s['scheduledAutomations']),
              ],
            ),
            const SizedBox(height: DialogFieldStyle.fieldGap),
            _buildCreateForm(s),
            const SizedBox(height: DialogFieldStyle.fieldGap),
            SizedBox(
              height: 200,
              child: TabBarView(
                controller: _tabs,
                children: [
                  _AutomationList(
                    emptyLabel: s['noAiActions'],
                    items: manual,
                    onRun: _runAutomation,
                    onDelete: (a) => state.deleteAutomation(a),
                    onTogglePin: _togglePin,
                    pinLabel: s['putOnBar'],
                    unpinLabel: s['takeOffBar'],
                  ),
                  _AutomationList(
                    emptyLabel: s['noAutomations'],
                    items: scheduled,
                    onRun: _runAutomation,
                    onDelete: (a) => state.deleteAutomation(a),
                  ),
                ],
              ),
            ),
          ],
      ),
    );
  }

  Widget _buildCreateForm(AppStrings s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _tabs.index == 0 ? s['createAiAction'] : s['createAutomation'],
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        AppDialogField(
          label: s['automationName'],
          child: TextField(
            controller: _nameController,
            decoration: DialogFieldStyle.decoration(),
          ),
        ),
        const SizedBox(height: DialogFieldStyle.fieldGap),
        AppDialogField(
          label: s['automationPrompt'],
          child: TextField(
            controller: _promptController,
            minLines: 2,
            maxLines: 4,
            decoration: DialogFieldStyle.decoration(),
          ),
        ),
        if (_tabs.index == 1) ...[
          const SizedBox(height: DialogFieldStyle.fieldGap),
          AppDialogField(
            label: s['schedule'],
            hint: s['scheduleCronHint'],
            child: TextField(
              controller: _scheduleController,
              decoration: DialogFieldStyle.decoration(),
            ),
          ),
        ],
        const SizedBox(height: DialogFieldStyle.fieldGap),
        AppDialogChoiceField<String>(
          label: s['applyMode'],
          options: [
            AppSegmentedOption(value: 'review', label: s['applyModeReview']),
            AppSegmentedOption(
              value: 'direct_apply',
              label: s['applyModeDirect'],
            ),
            AppSegmentedOption(
              value: 'notify_only',
              label: s['applyModeNotify'],
            ),
          ],
          selected: _applyMode,
          onSelected: (mode) => setState(() => _applyMode = mode),
        ),
        const SizedBox(height: DialogFieldStyle.fieldGap),
        ActionIconField(
          label: s['actionIcon'],
          valueLabel: s['actionIconChoose'],
          pickerTitle: s['actionIcon'],
          iconKey: _iconKey,
          onChanged: (key) => setState(() => _iconKey = key),
        ),
        if (_tabs.index == 0) ...[
          const SizedBox(height: DialogFieldStyle.fieldGap),
          AppDialogField(
            label: s['actionPlace'],
            hint: _barIsFull ? s['aiBarFull'] : s['actionPlaceHint'],
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: AppSegmentedToggle<bool>(
                options: [
                  AppSegmentedOption(value: false, label: s['actionPlaceMenu']),
                  AppSegmentedOption(value: true, label: s['putOnBar']),
                ],
                selected: _onBar,
                enabled: !_barIsFull,
                onSelected: (onBar) => setState(() => _onBar = onBar),
              ),
            ),
          ),
        ],
        const SizedBox(height: DialogFieldStyle.fieldGap),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: FilledButton(
            onPressed: _creating ? null : () {
              _kind = _tabs.index == 0
                  ? _AutomationKind.manual
                  : _AutomationKind.scheduled;
              _create();
            },
            child: Text(_creating ? s['aiRunning'] : s['create']),
          ),
        ),
      ],
    );
  }
}

enum _AutomationKind { manual, scheduled }

class _AutomationList extends StatelessWidget {
  const _AutomationList({
    required this.emptyLabel,
    required this.items,
    required this.onRun,
    required this.onDelete,
    this.onTogglePin,
    this.pinLabel,
    this.unpinLabel,
  });

  final String emptyLabel;
  final List<Automation> items;
  final Future<void> Function(Automation) onRun;
  final Future<void> Function(Automation) onDelete;

  /// Only actions can sit on the AI bar, so a scheduled list leaves this null.
  final Future<void> Function(Automation)? onTogglePin;
  final String? pinLabel;
  final String? unpinLabel;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(child: Text(emptyLabel));
    }
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = items[index];
        return ListTile(
          dense: true,
          leading: AppIcon(actionIcon(item.icon), size: 18),
          title: Text(item.name),
          subtitle: Text(
            item.prompt,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onTogglePin != null)
                IconButton(
                  tooltip: item.isOnBar ? unpinLabel : pinLabel,
                  icon: AppIcon(
                    item.isOnBar ? AppIcons.unpinFromBar : AppIcons.pinToBar,
                    size: 18,
                  ),
                  onPressed: () => onTogglePin!(item),
                ),
              IconButton(
                icon: const AppIcon(AppIcons.runNow, size: 18),
                onPressed: () => onRun(item),
              ),
              IconButton(
                icon: const AppIcon(AppIcons.trash, size: 18),
                onPressed: () => onDelete(item),
              ),
            ],
          ),
        );
      },
    );
  }
}
