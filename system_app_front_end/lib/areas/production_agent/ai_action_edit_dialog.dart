import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../ui/action_icon_picker.dart';
import '../ui/action_icons.dart';
import '../ui/adaptive_dialog.dart';
import '../ui/app_icons.dart';
import '../ui/app_segmented_toggle.dart';
import '../ui/dialog_field_style.dart';
import '../ui/dialog_metrics.dart';
import './agent_run_defaults.dart';
import './ai_action.dart';

/// Create or rewrite a saved AI action: name, prompt, apply mode, icon, seat.
///
/// Returns the saved row, or null if cancelled.
Future<AiAction?> showAiActionEditDialog({
  required BuildContext context,
  required AppState state,
  AiAction? action,
  int? initialTopicTypeId,
}) async {
  return showAppDialog<AiAction>(
    context: context,
    builder: (ctx) => _AiActionEditDialog(
      state: state,
      action: action,
      initialTopicTypeId: initialTopicTypeId,
    ),
  );
}

class _AiActionEditDialog extends StatefulWidget {
  const _AiActionEditDialog({
    required this.state,
    this.action,
    this.initialTopicTypeId,
  });

  final AppState state;
  final AiAction? action;
  final int? initialTopicTypeId;

  @override
  State<_AiActionEditDialog> createState() => _AiActionEditDialogState();
}

class _AiActionEditDialogState extends State<_AiActionEditDialog> {
  late final TextEditingController _name;
  late final TextEditingController _prompt;
  late String _applyMode;
  late String _iconKey;
  late bool _onBar;
  int? _topicTypeId;
  var _saving = false;

  bool get _isCreate => widget.action == null;

  @override
  void initState() {
    super.initState();
    final existing = widget.action;
    _name = TextEditingController(text: existing?.name ?? '');
    _prompt = TextEditingController(text: existing?.prompt ?? '');
    _applyMode = existing?.applyMode ?? defaultConsultApplyMode;
    _iconKey = (existing == null || existing.icon.isEmpty)
        ? defaultActionIconKey
        : existing.icon;
    _onBar = existing?.isOnBar ?? false;
    _topicTypeId = existing?.topicTypeId ?? widget.initialTopicTypeId;
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
      final AiAction saved;
      if (_isCreate) {
        saved = await widget.state.createAiAction(
          name: _name.text.trim(),
          prompt: _prompt.text.trim(),
          applyMode: _applyMode,
          icon: _iconKey,
          barSlot: _onBar ? widget.state.firstFreeAiBarSlot : null,
          topicTypeId: _topicTypeId,
        );
      } else {
        final existing = widget.action!;
        await widget.state.updateAiAction(existing, {
          'name': _name.text.trim(),
          'prompt': _prompt.text.trim(),
          'apply_mode': _applyMode,
          'icon': _iconKey,
          'topic_type_id': _topicTypeId,
          if (_onBar != existing.isOnBar)
            'bar_slot': _onBar ? widget.state.firstFreeAiBarSlot : null,
        });
        saved = widget.state.aiActions.firstWhere(
          (row) => row.id == existing.id,
          orElse: () => existing,
        );
      }
      if (mounted) Navigator.pop(context, saved);
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
      title: Text(
        _isCreate
            ? s['createAiAction']
            : s.editActionTitle(widget.action!.name),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
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
          if (widget.state.topicTypes.isNotEmpty)
            AppDialogPickerField(
              label: s['actionAppliesTo'],
              preview: const AppIcon(AppIcons.bringFile, size: 16),
              valueLabel: _typeLabel(),
              onTap: _pickType,
            ),
          if (widget.state.topicTypes.isNotEmpty)
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

  String _typeLabel() {
    final s = widget.state.strings;
    if (_topicTypeId == null) return s['actionAppliesEveryTopic'];
    final type = widget.state.topicTypeById(_topicTypeId);
    return type == null
        ? s['actionAppliesEveryTopic']
        : widget.state.topicTypeDisplayName(type);
  }

  Future<void> _pickType() async {
    final s = widget.state.strings;
    final picked = await showAppDialog<int>(
      context: context,
      builder: (ctx) => AppAdaptiveDialogShell(
        title: Text(s['actionAppliesTo']),
        width: AppDialogMetrics.wideWidth,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s['cancel']),
          ),
        ],
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                dense: true,
                selected: _topicTypeId == null,
                title: Text(s['actionAppliesEveryTopic']),
                onTap: () => Navigator.pop(ctx, -1),
              ),
              for (final type in widget.state.topicTypes)
                ListTile(
                  dense: true,
                  selected: type.id == _topicTypeId,
                  title: Text(widget.state.topicTypeDisplayName(type)),
                  onTap: () => Navigator.pop(ctx, type.id),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _topicTypeId = picked < 0 ? null : picked);
  }
}
