import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/l10n/app_strings.dart';
import '../ui/action_icon_picker.dart';
import '../ui/action_icons.dart';
import '../ui/adaptive_dialog.dart';
import '../ui/app_segmented_toggle.dart';
import '../ui/dialog_field_style.dart';
import '../ux/shortcuts/shortcut_catalog.dart';
import './agent_result_ui.dart';
import './agent_run_defaults.dart';

/// What the user asked the dialog for.
enum AgentPromptOutcome { run, save, saveAndRun }

/// A prompt, how to apply it, and — when the user chose to keep it — the
/// making of a saved action.
class AgentPromptRequest {
  const AgentPromptRequest({
    required this.prompt,
    required this.applyMode,
    required this.outcome,
    this.name = '',
    this.nameHe = '',
    this.iconKey = defaultActionIconKey,
    this.barSlot,
  });

  final String prompt;
  final String applyMode;
  final AgentPromptOutcome outcome;
  final String name;
  final String nameHe;
  final String iconKey;

  /// 1..6 to give the action a seat on the AI bar, null to leave it in the menu.
  final int? barSlot;

  bool get saves => outcome != AgentPromptOutcome.run;
  bool get runs => outcome != AgentPromptOutcome.save;
}

/// Ask the agent something, and keep the ask if it is worth repeating.
Future<void> runAgentPrompt(BuildContext context, AppState state) async {
  final s = state.strings;
  if (!state.hasAiContext || state.aiRunning) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s['aiNoContext'])),
    );
    return;
  }

  final request = await showAppDialog<AgentPromptRequest>(
    context: context,
    builder: (ctx) => AgentPromptDialog(state: state),
  );
  if (request == null || !context.mounted) return;

  try {
    if (request.saves) {
      await state.createAiAction(
        name: request.name,
        nameHe: request.nameHe,
        prompt: request.prompt,
        applyMode: request.applyMode,
        icon: request.iconKey,
        barSlot: request.barSlot,
        topicId: state.selectedTopic?.id,
      );
      if (!context.mounted) return;
      if (!request.runs) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s['actionSaved'])),
        );
        return;
      }
    }
    final result = await state.runAgentPrompt(
      request.prompt,
      applyMode: request.applyMode,
    );
    if (!context.mounted || result == null) return;
    await presentAgentRunResult(context, state, result);
  } catch (e) {
    if (!context.mounted) return;
    showAgentMessageSnackBar(context, e.toString());
  }
}

/// The agent's ask box.
///
/// It opens small — a prompt and how to apply it. "Save as action" grows it
/// into the form for a saved action, because naming and placing something is
/// only interesting once the user has decided to keep it.
class AgentPromptDialog extends StatefulWidget {
  const AgentPromptDialog({super.key, required this.state});

  final AppState state;

  @override
  State<AgentPromptDialog> createState() => _AgentPromptDialogState();
}

class _AgentPromptDialogState extends State<AgentPromptDialog> {
  final _prompt = TextEditingController();
  final _name = TextEditingController();
  final _nameHe = TextEditingController();
  var _applyMode = 'direct_apply';
  var _saving = false;
  var _iconKey = defaultActionIconKey;
  int? _barSlot;

  @override
  void initState() {
    super.initState();
    _prompt.addListener(_onTextChanged);
    _name.addListener(_onTextChanged);
    _nameHe.addListener(_onTextChanged);
    _barSlot = widget.state.firstFreeAiBarSlot;
  }

  @override
  void dispose() {
    _prompt.dispose();
    _name.dispose();
    _nameHe.dispose();
    super.dispose();
  }

  void _onTextChanged() => setState(() {});

  bool get _canRun => _prompt.text.trim().isNotEmpty;
  bool get _canSave =>
      _canRun &&
      _name.text.trim().isNotEmpty &&
      _nameHe.text.trim().isNotEmpty;

  AgentPromptRequest _request(AgentPromptOutcome outcome) => AgentPromptRequest(
    prompt: _prompt.text.trim(),
    applyMode: _applyMode,
    outcome: outcome,
    name: _name.text.trim(),
    nameHe: _nameHe.text.trim(),
    iconKey: _iconKey,
    barSlot: _barSlot,
  );

  void _close(AgentPromptOutcome outcome) =>
      Navigator.pop(context, _request(outcome));

  /// The key that fires a slot, so the choice reads as what it gives you.
  String _slotLabel(int slot) {
    final binding = widget.state.shortcutBindings.bindingFor(
      ShortcutActionIds.aiActionSlot(slot),
    );
    return binding.isValid ? binding.displayLabel() : '$slot';
  }

  String? _placeHint(AppStrings s) {
    if (_barSlot == null) return s['actionPlaceHint'];
    final taken = widget.state.aiActionInSlot(_barSlot!);
    return taken == null
        ? s['actionPlaceHint']
        : s.actionReplaces(widget.state.aiActionDisplayName(taken));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state.strings;

    return AppAdaptiveDialogShell(
      title: Text(s['aiAgent']),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s['cancel']),
        ),
        if (!_saving) ...[
          TextButton(
            onPressed: () => setState(() => _saving = true),
            child: Text(s['saveAsAction']),
          ),
          FilledButton(
            onPressed: _canRun ? () => _close(AgentPromptOutcome.run) : null,
            child: Text(s['run']),
          ),
        ] else ...[
          TextButton(
            onPressed: _canSave
                ? () => _close(AgentPromptOutcome.saveAndRun)
                : null,
            child: Text(s['saveAndRunAction']),
          ),
          FilledButton(
            onPressed: _canSave ? () => _close(AgentPromptOutcome.save) : null,
            child: Text(s['saveAction']),
          ),
        ],
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppDialogField(
            label: s['aiAgentPromptHint'],
            child: TextField(
              controller: _prompt,
              autofocus: true,
              maxLines: 4,
              decoration: DialogFieldStyle.decoration(),
            ),
          ),
          const SizedBox(height: DialogFieldStyle.fieldGap),
          AppDialogChoiceField<String>(
            label: s['consultApplyMode'],
            options: [
              AppSegmentedOption(
                value: 'review',
                label: s['consultApplyModeReview'],
              ),
              AppSegmentedOption(
                value: 'direct_apply',
                label: s['consultApplyModeDirect'],
              ),
            ],
            selected: _applyMode,
            onSelected: (mode) => setState(() => _applyMode = mode),
          ),
          if (_saving) ...[
            const SizedBox(height: DialogFieldStyle.fieldGap),
            AppDialogField(
              label: s['nameEnglish'],
              child: TextField(
                controller: _name,
                maxLines: 1,
                decoration: DialogFieldStyle.decoration(),
              ),
            ),
            const SizedBox(height: DialogFieldStyle.fieldGap),
            AppDialogField(
              label: s['nameHebrew'],
              child: TextField(
                controller: _nameHe,
                maxLines: 1,
                textDirection: TextDirection.rtl,
                decoration: DialogFieldStyle.decoration(),
              ),
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
              hint: _placeHint(s),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: AppSegmentedToggle<int>(
                  // 0 stands for the menu: a toggle needs a value per choice,
                  // and null is what "no slot" means downstream.
                  options: [
                    AppSegmentedOption(value: 0, label: s['actionPlaceMenu']),
                    for (var slot = 1; slot <= aiBarSlotCount; slot++)
                      AppSegmentedOption(value: slot, label: _slotLabel(slot)),
                  ],
                  selected: _barSlot ?? 0,
                  onSelected: (value) =>
                      setState(() => _barSlot = value == 0 ? null : value),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
