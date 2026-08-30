import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/l10n/app_strings.dart';
import '../ui/action_icon_picker.dart';
import '../ui/action_icons.dart';
import '../ui/adaptive_dialog.dart';
import '../ui/app_switch.dart';
import '../ui/app_icons.dart';
import '../ui/app_segmented_toggle.dart';
import '../ui/dialog_field_style.dart';
import '../ux/dialogs/dialog_choice_list.dart';
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
  late final TextEditingController _nameHe;
  late final TextEditingController _prompt;
  late String _applyMode;
  late String _iconKey;
  late bool _onBar;
  late _ActionScopeKind _scopeKind;
  int? _topicTypeId;
  int? _topicId;
  late bool _requiresUserInput;
  late final TextEditingController _userInputPrompt;
  var _saving = false;

  bool get _isCreate => widget.action == null;

  @override
  void initState() {
    super.initState();
    final existing = widget.action;
    _name = TextEditingController(text: existing?.name ?? '');
    _nameHe = TextEditingController(text: existing?.nameHe ?? '');
    _prompt = TextEditingController(text: existing?.prompt ?? '');
    _requiresUserInput = existing?.requiresUserInput ?? false;
    _userInputPrompt = TextEditingController(
      text: existing?.userInputPrompt ?? '',
    );
    _applyMode = existing?.applyMode ?? defaultConsultApplyMode;
    _iconKey = (existing == null || existing.icon.isEmpty)
        ? defaultActionIconKey
        : existing.icon;
    _onBar = existing?.isOnBar ?? false;
    if (existing != null) {
      if (existing.topicId != null) {
        _scopeKind = _ActionScopeKind.topic;
        _topicId = existing.topicId;
        _topicTypeId = existing.topicTypeId;
      } else if (existing.topicTypeId != null) {
        _scopeKind = _ActionScopeKind.type;
        _topicTypeId = existing.topicTypeId;
      } else {
        _scopeKind = _ActionScopeKind.all;
      }
    } else if (widget.initialTopicTypeId != null) {
      _scopeKind = _ActionScopeKind.type;
      _topicTypeId = widget.initialTopicTypeId;
    } else {
      _scopeKind = _ActionScopeKind.topic;
      _topicId = widget.state.selectedTopic?.id;
    }
    _name.addListener(() => setState(() {}));
    _nameHe.addListener(() => setState(() {}));
    _prompt.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _nameHe.dispose();
    _prompt.dispose();
    _userInputPrompt.dispose();
    super.dispose();
  }

  bool get _canSave =>
      _name.text.trim().isNotEmpty &&
      _nameHe.text.trim().isNotEmpty &&
      _prompt.text.trim().isNotEmpty;

  bool get _barIsFull => widget.state.firstFreeAiBarSlot == null;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final AiAction saved;
      if (_isCreate) {
        saved = await widget.state.createAiAction(
          name: _name.text.trim(),
          nameHe: _nameHe.text.trim(),
          prompt: _prompt.text.trim(),
          applyMode: _applyMode,
          icon: _iconKey,
          barSlot: _onBar ? widget.state.firstFreeAiBarSlot : null,
          topicTypeId: _scopeKind == _ActionScopeKind.type ? _topicTypeId : null,
          topicId: _scopeKind == _ActionScopeKind.topic ? _topicId : null,
          requiresUserInput: _requiresUserInput,
          userInputPrompt: _userInputPrompt.text.trim(),
        );
      } else {
        final existing = widget.action!;
        await widget.state.updateAiAction(existing, {
          'name': _name.text.trim(),
          'name_he': _nameHe.text.trim(),
          'prompt': _prompt.text.trim(),
          'apply_mode': _applyMode,
          'icon': _iconKey,
          'topic_id': _scopeKind == _ActionScopeKind.topic ? _topicId : null,
          'topic_type_id':
              _scopeKind == _ActionScopeKind.type ? _topicTypeId : null,
          if (_onBar != existing.isOnBar)
            'bar_slot': _onBar ? widget.state.firstFreeAiBarSlot : null,
          'requires_user_input': _requiresUserInput,
          'user_input_prompt': _userInputPrompt.text.trim(),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state.strings;

    return AppAdaptiveDialogShell(
      title: Text(
        _isCreate
            ? s['createAiAction']
            : s.editActionTitle(widget.state.aiActionDisplayName(widget.action!)),
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
            label: s['nameEnglish'],
            child: TextField(
              controller: _name,
              autofocus: true,
              textInputAction: TextInputAction.next,
              decoration: DialogFieldStyle.decoration(),
            ),
          ),
          const SizedBox(height: DialogFieldStyle.fieldGap),
          AppDialogField(
            label: s['nameHebrew'],
            child: TextField(
              controller: _nameHe,
              textDirection: TextDirection.rtl,
              textInputAction: TextInputAction.next,
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
          Row(
            children: [
              Expanded(child: Text(s['requiresUserInput'])),
              AppSwitch(
                value: _requiresUserInput,
                onChanged: (on) => setState(() => _requiresUserInput = on),
              ),
            ],
          ),
          if (_requiresUserInput) ...[
            const SizedBox(height: DialogFieldStyle.fieldGap),
            AppDialogField(
              label: s['userInputPrompt'],
              child: TextField(
                controller: _userInputPrompt,
                decoration: DialogFieldStyle.decoration(
                  hintText: s['userInputPromptHint'],
                ),
              ),
            ),
          ],
          const SizedBox(height: DialogFieldStyle.fieldGap),
          ActionIconField(
            label: s['actionIcon'],
            valueLabel: s['actionIconChoose'],
            pickerTitle: s['actionIcon'],
            iconKey: _iconKey,
            onChanged: (key) => setState(() => _iconKey = key),
          ),
          const SizedBox(height: DialogFieldStyle.fieldGap),
          AppDialogPickerField(
              label: s['actionAppliesTo'],
              preview: const AppIcon(AppIcons.bringFile, size: 16),
              valueLabel: _scopeLabel(),
              onTap: _pickScope,
            ),
          const SizedBox(height: DialogFieldStyle.fieldGap),
          AppDialogField(
            label: s['actionPlace'],
            hint: _barIsFull && !_onBar ? s['aiBarFull'] : s['actionPlaceHint'],
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: AppSegmentedToggle<bool>(
                options: [
                  AppSegmentedOption(value: false, label: s['actionPlaceMenu']),
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

  String _scopeLabel() {
    final s = widget.state.strings;
    switch (_scopeKind) {
      case _ActionScopeKind.all:
        return s['actionAppliesEveryTopic'];
      case _ActionScopeKind.type:
        final type = widget.state.topicTypeById(_topicTypeId);
        return type == null
            ? s['scopeTopicType']
            : widget.state.topicTypeDisplayName(type);
      case _ActionScopeKind.topic:
        final topic = widget.state.allTopics
            .where((t) => t.id == _topicId)
            .firstOrNull;
        if (topic == null) return s['actionAppliesThisTopic'];
        return widget.state.topicDisplayName(topic);
    }
  }

  Future<void> _pickScope() async {
    final s = widget.state.strings;
    final rows = <_ScopeChoice>[
      const _ScopeChoice(
        kind: _ActionScopeKind.all,
        labelKey: 'actionAppliesEveryTopic',
      ),
      for (final type in widget.state.topicTypes)
        _ScopeChoice(
          kind: _ActionScopeKind.type,
          typeId: type.id,
          label: widget.state.topicTypeDisplayName(type),
        ),
      for (final topic in widget.state.activeTopics)
          _ScopeChoice(
            kind: _ActionScopeKind.topic,
            topicId: topic.id,
            label: widget.state.topicDisplayName(topic),
          ),
    ];
    var initial = 0;
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].matches(_scopeKind, _topicId, _topicTypeId)) {
        initial = i;
        break;
      }
    }
    final picked = await showAppChoiceDialog<_ScopeChoice>(
      context: context,
      title: s['actionAppliesTo'],
      cancelLabel: s['cancel'],
      items: rows,
      initialIndex: initial,
      itemBuilder: (context, row, _) => DialogChoiceText(row.title(s)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _scopeKind = picked.kind;
      _topicId = picked.topicId;
      _topicTypeId = picked.typeId;
    });
  }
}

enum _ActionScopeKind { all, type, topic }

class _ScopeChoice {
  const _ScopeChoice({
    required this.kind,
    this.typeId,
    this.topicId,
    this.label,
    this.labelKey,
  });

  final _ActionScopeKind kind;
  final int? typeId;
  final int? topicId;
  final String? label;
  final String? labelKey;

  bool matches(_ActionScopeKind kind, int? topicId, int? typeId) {
    if (this.kind != kind) return false;
    if (kind == _ActionScopeKind.topic) return this.topicId == topicId;
    if (kind == _ActionScopeKind.type) return this.typeId == typeId;
    return true;
  }

  String title(AppStrings strings) =>
      label ?? (labelKey != null ? strings[labelKey!] : '');
}

