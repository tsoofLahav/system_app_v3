import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/l10n/app_strings.dart';
import '../production_agent/agent_run_defaults.dart';
import '../ui/adaptive_dialog.dart';
import '../ui/app_colors.dart';
import '../ui/app_icons.dart';
import '../ui/app_segmented_toggle.dart';
import '../ui/app_typography.dart';
import '../ui/dialog_field_style.dart';
import '../ui/dialog_metrics.dart';
import '../ux/topic/topic_appearance.dart';
import '../ux/widgets/topic_emoji.dart';
import './automation.dart';
import './schedule_format.dart';

/// Create or rewrite an automation: scope, when it fires, and what it does.
Future<bool> showAutomationBuilderDialog({
  required BuildContext context,
  required AppState state,
  Automation? automation,
}) async {
  final saved = await showAppDialog<bool>(
    context: context,
    builder: (ctx) => _AutomationBuilderDialog(
      state: state,
      automation: automation,
    ),
  );
  return saved ?? false;
}

class _AutomationBuilderDialog extends StatefulWidget {
  const _AutomationBuilderDialog({required this.state, this.automation});

  final AppState state;
  final Automation? automation;

  @override
  State<_AutomationBuilderDialog> createState() =>
      _AutomationBuilderDialogState();
}

class _AutomationBuilderDialogState extends State<_AutomationBuilderDialog> {
  late final TextEditingController _name;
  late String _scopeKind;
  int? _topicId;
  String _topicType = 'process';
  late AutomationSchedule _schedule;
  late bool _enabled;
  late List<Map<String, dynamic>> _steps;
  var _saving = false;

  AppState get state => widget.state;
  AppStrings get s => state.strings;
  bool get _isEdit => widget.automation != null;

  static const _topicTypes = ['project', 'process', 'area', 'other'];

  @override
  void initState() {
    super.initState();
    final existing = widget.automation;
    _name = TextEditingController(text: existing?.name ?? '');
    _name.addListener(() => setState(() {}));
    final scope = existing?.scope ?? _defaultScope();
    _scopeKind = AutomationScope.kindOf(scope);
    _topicId = scope['topic_id'] as int? ?? state.selectedTopic?.id;
    _topicType = (scope['tag'] as String?) ?? 'process';
    _schedule = AutomationSchedule.parse(existing?.schedule);
    _enabled = existing?.enabled ?? true;
    _steps = [
      for (final step in existing?.steps ?? const <Map<String, dynamic>>[])
        Map<String, dynamic>.from(step),
    ];
  }

  Map<String, dynamic> _defaultScope() {
    final topic = state.selectedTopic;
    return topic == null
        ? AutomationScope.everywhere()
        : AutomationScope.oneTopic(topic.id);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Map<String, dynamic> _scope() {
    return switch (_scopeKind) {
      AutomationScope.topic when _topicId != null =>
        AutomationScope.oneTopic(_topicId!),
      AutomationScope.topicType => AutomationScope.ofType(_topicType),
      _ => AutomationScope.everywhere(),
    };
  }

  bool get _canSave {
    if (_name.text.trim().isEmpty || _steps.isEmpty) return false;
    if (_scopeKind == AutomationScope.topic && _topicId == null) return false;
    return _steps.every(_stepIsReady);
  }

  bool _stepIsReady(Map<String, dynamic> step) {
    final kind = step['kind'] as String? ?? '';
    if (kind == StepKinds.ai) {
      final hasPrompt = (step['prompt'] as String? ?? '').trim().isNotEmpty;
      return hasPrompt || step['action_id'] != null;
    }
    if (kind == StepKinds.createFile) {
      if ((step['name'] as String? ?? '').trim().isEmpty) return false;
      final needsTopic = _scopeKind != AutomationScope.topic;
      return !needsTopic || step['topic_id'] != null;
    }
    return StepKinds.all.contains(kind);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      if (_isEdit) {
        await state.updateAutomation(widget.automation!, {
          'name': _name.text.trim(),
          'scope': _scope(),
          'trigger': {'type': 'schedule'},
          'steps': _steps,
          'schedule': _schedule.toDsl(),
          'timezone': AutomationSchedule.defaultTimezone,
          'enabled': _enabled,
        });
      } else {
        await state.createAutomation(
          name: _name.text.trim(),
          scope: _scope(),
          trigger: const {'type': 'schedule'},
          steps: _steps,
          schedule: _schedule.toDsl(),
          timezone: AutomationSchedule.defaultTimezone,
          enabled: _enabled,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _addStep() async {
    final kind = await _pickStepKind();
    if (kind == null || !mounted) return;
    setState(() {
      final step = <String, dynamic>{'kind': kind};
      if (kind == StepKinds.ai) {
        step['apply_mode'] = defaultAutomationApplyMode;
      }
      if (kind == StepKinds.createFile) {
        step['name'] = 'Week of {date}';
      }
      _steps = [..._steps, step];
    });
  }

  Future<String?> _pickStepKind() {
    return showAppDialog<String>(
      context: context,
      builder: (ctx) => AppAdaptiveDialogShell(
        title: Text(s['addStep']),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s['cancel']),
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final kind in StepKinds.all)
              ListTile(
                dense: true,
                title: Text(_stepLabel(kind)),
                onTap: () => Navigator.pop(ctx, kind),
              ),
          ],
        ),
      ),
    );
  }

  String _stepLabel(String kind) => switch (kind) {
        StepKinds.ai => s['stepAi'],
        StepKinds.createFile => s['stepCreateFile'],
        StepKinds.unmarkTasks => s['stepUnmarkTasks'],
        StepKinds.archiveFiles => s['stepArchiveFiles'],
        _ => kind,
      };

  String _topicLabel(int? id) {
    if (id == null) return s['pickTopic'];
    for (final topic in state.activeTopics) {
      if (topic.id == id) return state.topicDisplayName(topic);
    }
    return s['pickTopic'];
  }

  Future<int?> _pickTopic({int? currentId}) {
    return showAppDialog<int>(
      context: context,
      builder: (ctx) => AppAdaptiveDialogShell(
        title: Text(s['pickTopic']),
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
              for (final topic in state.activeTopics)
                ListTile(
                  dense: true,
                  selected: topic.id == currentId,
                  leading: TopicEmoji(value: topic.icon, size: 18),
                  title: Text(state.topicDisplayName(topic)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(
                      color: TopicAppearance.colorFromHex(topic.color)
                          .withValues(alpha: 0.35),
                    ),
                  ),
                  onTap: () => Navigator.pop(ctx, topic.id),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _replaceStep(int index, Map<String, dynamic> step) {
    setState(() {
      _steps = [
        for (var i = 0; i < _steps.length; i++) i == index ? step : _steps[i],
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppAdaptiveDialogShell(
      title: Text(
        _isEdit
            ? s.editAutomationTitle(widget.automation!.name)
            : s['createAutomation'],
      ),
      width: AppDialogMetrics.wideWidth,
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
          AppDialogChoiceField<String>(
            label: s['automationScopeKind'],
            options: [
              AppSegmentedOption(
                value: AutomationScope.all,
                label: s['scopeAll'],
              ),
              AppSegmentedOption(
                value: AutomationScope.topic,
                label: s['scopeOneTopic'],
              ),
              AppSegmentedOption(
                value: AutomationScope.topicType,
                label: s['scopeTopicType'],
              ),
            ],
            selected: _scopeKind,
            onSelected: (kind) => setState(() => _scopeKind = kind),
          ),
          if (_scopeKind == AutomationScope.topic) ...[
            const SizedBox(height: DialogFieldStyle.fieldGap),
            AppDialogPickerField(
              label: s['pickTopic'],
              preview: const AppIcon(AppIcons.bringFile, size: 16),
              valueLabel: _topicLabel(_topicId),
              onTap: () async {
                final id = await _pickTopic(currentId: _topicId);
                if (id != null) setState(() => _topicId = id);
              },
            ),
          ],
          if (_scopeKind == AutomationScope.topicType) ...[
            const SizedBox(height: DialogFieldStyle.fieldGap),
            AppDialogChoiceField<String>(
              label: s['scopeTopicType'],
              options: [
                for (final tag in _topicTypes)
                  AppSegmentedOption(
                    value: tag,
                    label: s.topicTypeLabel(tag),
                  ),
              ],
              selected: _topicType,
              onSelected: (tag) => setState(() => _topicType = tag),
            ),
          ],
          const SizedBox(height: DialogFieldStyle.fieldGap),
          _ScheduleFields(
            schedule: _schedule,
            strings: s,
            onChanged: (next) => setState(() => _schedule = next),
          ),
          const SizedBox(height: DialogFieldStyle.fieldGap),
          AppDialogChoiceField<bool>(
            label: s['enabled'],
            options: [
              AppSegmentedOption(value: true, label: s['enabled']),
              AppSegmentedOption(value: false, label: s['disabled']),
            ],
            selected: _enabled,
            onSelected: (on) => setState(() => _enabled = on),
          ),
          const SizedBox(height: DialogFieldStyle.fieldGap),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(s['automationSteps'], style: DialogFieldStyle.labelStyle),
          ),
          const SizedBox(height: DialogFieldStyle.labelGap),
          if (_steps.isEmpty)
            Text(s['addStepHint'], style: AppTypography.metaStyle),
          for (var i = 0; i < _steps.length; i++) _stepCard(i),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: _addStep,
              icon: const AppIcon(AppIcons.add, size: 16),
              label: Text(s['addStep']),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepCard(int index) {
    final step = _steps[index];
    final kind = step['kind'] as String? ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: DialogFieldStyle.fieldGap),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: AppColors.noteBorder.withValues(alpha: 0.68),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 4, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(_stepLabel(kind), style: AppTypography.metaStyle),
                  ),
                  IconButton(
                    tooltip: s['moveStepUp'],
                    onPressed: index == 0
                        ? null
                        : () => setState(() {
                              final next = [..._steps];
                              final taken = next.removeAt(index);
                              next.insert(index - 1, taken);
                              _steps = next;
                            }),
                    icon: const AppIcon(AppIcons.chevronUp, size: 16),
                  ),
                  IconButton(
                    tooltip: s['moveStepDown'],
                    onPressed: index == _steps.length - 1
                        ? null
                        : () => setState(() {
                              final next = [..._steps];
                              final taken = next.removeAt(index);
                              next.insert(index + 1, taken);
                              _steps = next;
                            }),
                    icon: const AppIcon(AppIcons.chevronDown, size: 16),
                  ),
                  IconButton(
                    tooltip: s['delete'],
                    onPressed: () => setState(() {
                      _steps = [
                        for (var i = 0; i < _steps.length; i++)
                          if (i != index) _steps[i],
                      ];
                    }),
                    icon: const AppIcon(AppIcons.trash, size: 16),
                  ),
                ],
              ),
              if (kind == StepKinds.ai) _aiFields(index, step),
              if (kind == StepKinds.createFile) _createFileFields(index, step),
              if (kind == StepKinds.archiveFiles) _archiveFields(index, step),
              if (kind == StepKinds.unmarkTasks)
                Text(s['unmarkAllInScope'], style: AppTypography.metaStyle),
            ],
          ),
        ),
      ),
    );
  }

  Widget _aiFields(int index, Map<String, dynamic> step) {
    final usingSaved = step['action_id'] != null;
    final actions = state.aiActions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppDialogChoiceField<bool>(
          label: s['stepAiSource'],
          options: [
            AppSegmentedOption(value: true, label: s['stepAiSaved']),
            AppSegmentedOption(value: false, label: s['stepAiWrite']),
          ],
          selected: usingSaved,
          onSelected: (saved) {
            final next = Map<String, dynamic>.from(step);
            if (saved) {
              next.remove('prompt');
              next['action_id'] = actions.isEmpty ? null : actions.first.id;
            } else {
              next.remove('action_id');
              next['prompt'] = '';
            }
            _replaceStep(index, next);
          },
        ),
        const SizedBox(height: DialogFieldStyle.fieldGap),
        if (usingSaved)
          actions.isEmpty
              ? Text(s['noSavedActionsForStep'], style: AppTypography.metaStyle)
              : AppDialogPickerField(
                  label: s['pickAiAction'],
                  preview: const AppIcon(AppIcons.ai, size: 16),
                  valueLabel: _actionLabel(step['action_id'] as int?),
                  onTap: () async {
                    final id = await _pickSavedAction(step['action_id'] as int?);
                    if (id == null) return;
                    final next = Map<String, dynamic>.from(step);
                    next['action_id'] = id;
                    _replaceStep(index, next);
                  },
                )
        else
          AppDialogField(
            label: s['automationPrompt'],
            child: _KeepTextField(
              key: ValueKey('ai-$index'),
              value: step['prompt'] as String? ?? '',
              minLines: 2,
              maxLines: 4,
              onChanged: (value) {
                final next = Map<String, dynamic>.from(step);
                next['prompt'] = value;
                _replaceStep(index, next);
              },
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
          ],
          selected:
              (step['apply_mode'] as String?) ?? defaultAutomationApplyMode,
          onSelected: (mode) {
            final next = Map<String, dynamic>.from(step);
            next['apply_mode'] = mode;
            _replaceStep(index, next);
          },
        ),
      ],
    );
  }

  String _actionLabel(int? id) {
    if (id == null) return s['pickAiAction'];
    for (final action in state.aiActions) {
      if (action.id == id) return action.name;
    }
    return s['pickAiAction'];
  }

  Future<int?> _pickSavedAction(int? currentId) {
    return showAppDialog<int>(
      context: context,
      builder: (ctx) => AppAdaptiveDialogShell(
        title: Text(s['pickAiAction']),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s['cancel']),
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final action in state.aiActions)
              ListTile(
                dense: true,
                selected: action.id == currentId,
                title: Text(action.name),
                subtitle: Text(
                  action.prompt,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Navigator.pop(ctx, action.id),
              ),
          ],
        ),
      ),
    );
  }

  Widget _createFileFields(int index, Map<String, dynamic> step) {
    final needsTopic = _scopeKind != AutomationScope.topic;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppDialogField(
          label: s['fileNamePattern'],
          hint: s['fileNamePatternHint'],
          child: _KeepTextField(
            key: ValueKey('file-$index'),
            value: step['name'] as String? ?? '',
            onChanged: (value) {
              final next = Map<String, dynamic>.from(step);
              next['name'] = value;
              _replaceStep(index, next);
            },
          ),
        ),
        if (needsTopic) ...[
          const SizedBox(height: DialogFieldStyle.fieldGap),
          AppDialogPickerField(
            label: s['pickTopic'],
            preview: const AppIcon(AppIcons.bringFile, size: 16),
            valueLabel: _topicLabel(step['topic_id'] as int?),
            onTap: () async {
              final id = await _pickTopic(currentId: step['topic_id'] as int?);
              if (id == null) return;
              final next = Map<String, dynamic>.from(step);
              next['topic_id'] = id;
              _replaceStep(index, next);
            },
          ),
        ],
      ],
    );
  }

  Widget _archiveFields(int index, Map<String, dynamic> step) {
    final days = step['older_than_days'];
    final all = days == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppDialogChoiceField<bool>(
          label: s['stepArchiveFiles'],
          options: [
            AppSegmentedOption(value: true, label: s['archiveAllInScope']),
            AppSegmentedOption(value: false, label: s['archiveOlderThan']),
          ],
          selected: all,
          onSelected: (useAll) {
            final next = Map<String, dynamic>.from(step);
            if (useAll) {
              next.remove('older_than_days');
            } else {
              next['older_than_days'] = 30;
            }
            _replaceStep(index, next);
          },
        ),
        if (!all) ...[
          const SizedBox(height: DialogFieldStyle.fieldGap),
          AppDialogField(
            label: s['days'],
            child: _KeepTextField(
              key: ValueKey('days-$index'),
              value: '$days',
              keyboardType: TextInputType.number,
              onChanged: (value) {
                final parsed = int.tryParse(value.trim());
                if (parsed == null || parsed <= 0) return;
                final next = Map<String, dynamic>.from(step);
                next['older_than_days'] = parsed;
                _replaceStep(index, next);
              },
            ),
          ),
        ],
      ],
    );
  }
}

/// A text field that keeps its own controller so typing does not rebuild it
/// out from under the caret.
class _KeepTextField extends StatefulWidget {
  const _KeepTextField({
    super.key,
    required this.value,
    required this.onChanged,
    this.minLines = 1,
    this.maxLines = 1,
    this.keyboardType,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final int minLines;
  final int maxLines;
  final TextInputType? keyboardType;

  @override
  State<_KeepTextField> createState() => _KeepTextFieldState();
}

class _KeepTextFieldState extends State<_KeepTextField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_KeepTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && _controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      minLines: widget.minLines,
      maxLines: widget.maxLines,
      keyboardType: widget.keyboardType,
      decoration: DialogFieldStyle.decoration(),
      onChanged: widget.onChanged,
    );
  }
}

class _ScheduleFields extends StatelessWidget {
  const _ScheduleFields({
    required this.schedule,
    required this.strings,
    required this.onChanged,
  });

  final AutomationSchedule schedule;
  final AppStrings strings;
  final ValueChanged<AutomationSchedule> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = strings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppDialogChoiceField<String>(
          label: s['schedule'],
          options: [
            AppSegmentedOption(value: 'daily', label: s['onceADay']),
            AppSegmentedOption(value: 'weekly', label: s['onceAWeek']),
            AppSegmentedOption(value: 'monthly', label: s['onceAMonth']),
          ],
          selected: schedule.kind,
          onSelected: (kind) => onChanged(schedule.copyWith(kind: kind)),
        ),
        if (schedule.kind != 'daily') ...[
          const SizedBox(height: DialogFieldStyle.fieldGap),
          AppDialogChoiceField<String>(
            label: s['dayOfWeek'],
            options: [
              for (final day in AutomationSchedule.weekdays)
                AppSegmentedOption(
                  value: day,
                  label: s[AutomationSchedule.weekdayKeys[day]!],
                ),
            ],
            selected: schedule.weekday,
            onSelected: (day) => onChanged(schedule.copyWith(weekday: day)),
          ),
        ],
        if (schedule.kind == 'monthly') ...[
          const SizedBox(height: DialogFieldStyle.fieldGap),
          AppDialogChoiceField<String>(
            label: s['placementInMonth'],
            options: [
              for (final place in AutomationSchedule.placements)
                AppSegmentedOption(value: place, label: s[place]),
            ],
            selected: schedule.placement,
            onSelected: (place) =>
                onChanged(schedule.copyWith(placement: place)),
          ),
        ],
        const SizedBox(height: DialogFieldStyle.fieldGap),
        AppDialogField(
          label: s['time'],
          hint: s['automationTimeHelp'],
          child: _KeepTextField(
            value: schedule.time,
            onChanged: (value) => onChanged(schedule.copyWith(time: value)),
          ),
        ),
      ],
    );
  }
}
