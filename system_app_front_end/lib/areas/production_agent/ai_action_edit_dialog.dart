import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../ui/action_icon_picker.dart';
import '../ui/action_icons.dart';
import '../ui/adaptive_dialog.dart';
import '../ui/app_icons.dart';
import '../ui/app_segmented_toggle.dart';
import '../ui/app_typography.dart';
import '../ui/app_colors.dart';
import '../ui/dialog_field_style.dart';
import './agent_run_defaults.dart';
import './ai_action.dart';
import './ai_action_scope.dart';

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
  late AiActionScopeKind _scopeKind;
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
        _scopeKind = AiActionScopeKind.topic;
        _topicId = existing.topicId;
        _topicTypeId = existing.topicTypeId;
      } else if (existing.topicTypeId != null) {
        _scopeKind = AiActionScopeKind.type;
        _topicTypeId = existing.topicTypeId;
      } else {
        _scopeKind = AiActionScopeKind.all;
      }
    } else {
      final initial = defaultAiActionScope(
        widget.state,
        initialTopicTypeId: widget.initialTopicTypeId,
      );
      _scopeKind = initial.kind;
      _topicId = initial.topicId;
      _topicTypeId = initial.typeId;
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
          barSlot: _scopeKind == AiActionScopeKind.topic
              ? null
              : (_onBar ? widget.state.firstFreeAiBarSlot : null),
          topicTypeId: _scopeKind == AiActionScopeKind.type
              ? _topicTypeId
              : null,
          topicId: _scopeKind == AiActionScopeKind.topic ? _topicId : null,
          requiresUserInput: _requiresUserInput,
          userInputPrompt: _userInputPrompt.text.trim(),
        );
      } else {
        final existing = widget.action!;
        final leavingTopic =
            existing.topicId != null && _scopeKind != AiActionScopeKind.topic;
        await widget.state.updateAiAction(existing, {
          'name': _name.text.trim(),
          'name_he': _nameHe.text.trim(),
          'prompt': _prompt.text.trim(),
          'apply_mode': _applyMode,
          'icon': _iconKey,
          'topic_id': _scopeKind == AiActionScopeKind.topic ? _topicId : null,
          'topic_type_id': _scopeKind == AiActionScopeKind.type
              ? _topicTypeId
              : null,
          if (_scopeKind != AiActionScopeKind.topic &&
              (_onBar != existing.isOnBar || leavingTopic))
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
            : s.editActionTitle(
                widget.state.aiActionDisplayName(widget.action!),
              ),
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
          AppDialogChoiceField<bool>(
            label: s['requiresUserInput'],
            options: [
              AppSegmentedOption(value: true, label: s['requiresUserInputYes']),
              AppSegmentedOption(value: false, label: s['requiresUserInputNo']),
            ],
            selected: _requiresUserInput,
            onSelected: (needed) => setState(() => _requiresUserInput = needed),
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
            valueLabel: aiActionScopeLabel(
              widget.state,
              kind: _scopeKind,
              topicId: _topicId,
              typeId: _topicTypeId,
            ),
            onTap: _pickScope,
          ),
          if (_scopeKind == AiActionScopeKind.topic) ...[
            const SizedBox(height: DialogFieldStyle.fieldGap),
            Text(
              s['actionPlaceTopicHint'],
              style: AppTypography.metaStyle.copyWith(
                color: AppColors.textHint,
              ),
            ),
          ] else ...[
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

  Future<void> _pickScope() async {
    final picked = await pickAiActionScope(
      context: context,
      state: widget.state,
      kind: _scopeKind,
      topicId: _topicId,
      typeId: _topicTypeId,
      excludeActionId: widget.action?.id,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _scopeKind = picked.kind;
      _topicId = picked.topicId;
      _topicTypeId = picked.typeId;
    });
  }
}
