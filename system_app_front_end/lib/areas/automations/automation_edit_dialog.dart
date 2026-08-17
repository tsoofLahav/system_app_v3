import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../ui/action_icon_picker.dart';
import '../ui/action_icons.dart';
import '../ui/adaptive_dialog.dart';
import '../ui/app_segmented_toggle.dart';
import '../ui/dialog_field_style.dart';
import './automation.dart';

/// Rewrite a saved action or a scheduled automation.
///
/// One editor for both, because they are one record: a schedule field appears
/// for the scheduled ones, an icon and a seat for the actions. Returns true
/// when something was saved.
Future<bool> showAutomationEditDialog({
  required BuildContext context,
  required AppState state,
  required Automation automation,
}) async {
  final saved = await showAppDialog<bool>(
    context: context,
    builder: (ctx) => _AutomationEditDialog(state: state, automation: automation),
  );
  return saved ?? false;
}

class _AutomationEditDialog extends StatefulWidget {
  const _AutomationEditDialog({required this.state, required this.automation});

  final AppState state;
  final Automation automation;

  @override
  State<_AutomationEditDialog> createState() => _AutomationEditDialogState();
}

class _AutomationEditDialogState extends State<_AutomationEditDialog> {
  late final TextEditingController _name;
  late final TextEditingController _prompt;
  late final TextEditingController _schedule;
  late String _applyMode;
  late String _iconKey;
  late bool _onBar;
  var _saving = false;

  Automation get _automation => widget.automation;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: _automation.name);
    _prompt = TextEditingController(text: _automation.prompt);
    _schedule = TextEditingController(text: _automation.schedule ?? '');
    _applyMode = _automation.applyMode;
    _iconKey = _automation.icon.isEmpty ? defaultActionIconKey : _automation.icon;
    _onBar = _automation.isOnBar;
    _name.addListener(_onTextChanged);
    _prompt.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _name.dispose();
    _prompt.dispose();
    _schedule.dispose();
    super.dispose();
  }

  void _onTextChanged() => setState(() {});

  bool get _canSave =>
      _name.text.trim().isNotEmpty && _prompt.text.trim().isNotEmpty;

  bool get _barIsFull => widget.state.firstFreeAiBarSlot == null;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.state.updateAutomation(_automation, {
        'name': _name.text.trim(),
        'prompt': _prompt.text.trim(),
        'apply_mode': _applyMode,
        if (_automation.isScheduled) 'schedule': _schedule.text.trim(),
        if (!_automation.isScheduled) 'icon': _iconKey,
        // Only a real change of seat is sent; saving a rename must not
        // shuffle the bar.
        if (!_automation.isScheduled && _onBar != _automation.isOnBar)
          'bar_slot': _onBar ? widget.state.firstFreeAiBarSlot : null,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state.strings;

    return AppAdaptiveDialogShell(
      title: Text(s.editActionTitle(_automation.name)),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: Text(s['cancel']),
        ),
        FilledButton(
          onPressed: _canSave && !_saving ? _save : null,
          child: Text(s['save']),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppDialogField(
            label: s['automationName'],
            child: TextField(
              controller: _name,
              decoration: DialogFieldStyle.decoration(),
            ),
          ),
          const SizedBox(height: DialogFieldStyle.fieldGap),
          AppDialogField(
            label: s['automationPrompt'],
            child: TextField(
              controller: _prompt,
              minLines: 2,
              maxLines: 4,
              decoration: DialogFieldStyle.decoration(),
            ),
          ),
          if (_automation.isScheduled) ...[
            const SizedBox(height: DialogFieldStyle.fieldGap),
            AppDialogField(
              label: s['schedule'],
              hint: s['scheduleCronHint'],
              child: TextField(
                controller: _schedule,
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
          if (!_automation.isScheduled) ...[
            const SizedBox(height: DialogFieldStyle.fieldGap),
            ActionIconField(
              label: s['actionIcon'],
              valueLabel: s['actionIconChoose'],
              pickerTitle: s['actionIcon'],
              iconKey: _iconKey,
              onChanged: (key) => setState(() => _iconKey = key),
            ),
            const SizedBox(height: DialogFieldStyle.fieldGap),
            AppDialogField(
              label: s['actionPlace'],
              hint: _barIsFull && !_onBar
                  ? s['aiBarFull']
                  : s['actionPlaceHint'],
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: AppSegmentedToggle<bool>(
                  options: [
                    AppSegmentedOption(
                      value: false,
                      label: s['actionPlaceMenu'],
                    ),
                    AppSegmentedOption(value: true, label: s['putOnBar']),
                  ],
                  selected: _onBar,
                  enabled: !_barIsFull || _onBar,
                  onSelected: (onBar) => setState(() => _onBar = onBar),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
