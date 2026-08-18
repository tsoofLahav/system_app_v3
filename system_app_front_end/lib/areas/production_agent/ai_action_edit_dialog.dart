import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../ui/action_icon_picker.dart';
import '../ui/action_icons.dart';
import '../ui/adaptive_dialog.dart';
import '../ui/app_segmented_toggle.dart';
import '../ui/dialog_field_style.dart';
import './ai_action.dart';

/// Rewrite a saved AI action: name, prompt, apply mode, icon, seat.
Future<bool> showAiActionEditDialog({
  required BuildContext context,
  required AppState state,
  required AiAction action,
}) async {
  final saved = await showAppDialog<bool>(
    context: context,
    builder: (ctx) => _AiActionEditDialog(state: state, action: action),
  );
  return saved ?? false;
}

class _AiActionEditDialog extends StatefulWidget {
  const _AiActionEditDialog({required this.state, required this.action});

  final AppState state;
  final AiAction action;

  @override
  State<_AiActionEditDialog> createState() => _AiActionEditDialogState();
}

class _AiActionEditDialogState extends State<_AiActionEditDialog> {
  late final TextEditingController _name;
  late final TextEditingController _prompt;
  late String _applyMode;
  late String _iconKey;
  late bool _onBar;
  var _saving = false;

  AiAction get _action => widget.action;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: _action.name);
    _prompt = TextEditingController(text: _action.prompt);
    _applyMode = _action.applyMode;
    _iconKey = _action.icon.isEmpty ? defaultActionIconKey : _action.icon;
    _onBar = _action.isOnBar;
    _name.addListener(() => setState(() {}));
    _prompt.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _prompt.dispose();
    super.dispose();
  }

  bool get _canSave =>
      _name.text.trim().isNotEmpty && _prompt.text.trim().isNotEmpty;

  bool get _barIsFull => widget.state.firstFreeAiBarSlot == null;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.state.updateAiAction(_action, {
        'name': _name.text.trim(),
        'prompt': _prompt.text.trim(),
        'apply_mode': _applyMode,
        'icon': _iconKey,
        if (_onBar != _action.isOnBar)
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
      title: Text(s.editActionTitle(_action.name)),
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
            label: s['actionName'],
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
          const SizedBox(height: DialogFieldStyle.fieldGap),
          AppDialogField(
            label: s['actionPlace'],
            hint: _barIsFull && !_onBar ? s['aiBarFull'] : s['actionPlaceHint'],
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
      ),
    );
  }
}
