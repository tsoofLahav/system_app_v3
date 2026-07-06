import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_state.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/models/automation_rule.dart';
import '../../core/models/view_section.dart';
import '../../core/registry/view_registry.dart';
import '../../design_system/app_colors.dart';
import '../../design_system/app_icons.dart';
import '../../design_system/app_switch.dart';
import '../../design_system/app_typography.dart';
import '../../design_system/bilingual_layout.dart';
import '../../design_system/glass_surface.dart';

Future<void> showAutomationDialog({
  required BuildContext context,
  required AppState state,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AutomationDialog(state: state),
  );
}

InputDecoration _automationFieldDecoration(String label, {String? helperText}) {
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: BorderSide(
      color: AppColors.noteBorder.withValues(alpha: 0.58),
      width: 0.8,
    ),
  );
  return InputDecoration(
    labelText: label,
    helperText: helperText,
    floatingLabelBehavior: FloatingLabelBehavior.always,
    isDense: true,
    filled: false,
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    enabledBorder: border,
    focusedBorder: border.copyWith(
      borderSide: BorderSide(
        color: AppColors.primary.withValues(alpha: 0.54),
        width: 0.9,
      ),
    ),
    border: border,
  );
}

TextStyle _automationDropdownTextStyle() => AppTypography.noteBodyStyle
    .copyWith(color: AppColors.text.withValues(alpha: 0.92), fontSize: 12);

Color _automationDropdownColor() => AppColors.noteTop.withValues(alpha: 0.96);

BorderRadius _automationDropdownRadius() => BorderRadius.circular(14);

Widget _automationDropdownItem(String label) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Text(label),
  );
}

Widget _compactDropdown({required double width, required Widget child}) {
  return Align(
    alignment: AlignmentDirectional.centerStart,
    child: SizedBox(width: width, child: child),
  );
}

class AutomationDialog extends StatefulWidget {
  const AutomationDialog({super.key, required this.state});

  final AppState state;

  @override
  State<AutomationDialog> createState() => _AutomationDialogState();
}

class _AutomationDialogState extends State<AutomationDialog> {
  var _ensuringRules = true;

  @override
  void initState() {
    super.initState();
    _ensureRules();
  }

  Future<void> _ensureRules() async {
    try {
      await widget.state.ensureMainAutomationRules();
    } catch (_) {
      // The menu should stay open even if the backend is temporarily unavailable.
    } finally {
      if (mounted) {
        setState(() => _ensuringRules = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        final s = widget.state.strings;
        final definitionKeys = widget.state.automationDefinitions
            .map((definition) => definition.key)
            .toSet();
        final rules = widget.state.automationRules
            .where((rule) => definitionKeys.contains(rule.key))
            .toList();

        return AppGlassDialog(
          title: Text(s['automations']),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(s['ok']),
            ),
          ],
          child: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_ensuringRules)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                else if (rules.isEmpty)
                  Text(
                    s['noAutomations'],
                    style: AppTypography.noteBodyStyle,
                    textAlign: TextAlign.start,
                  )
                else
                  for (final rule in rules)
                    _AutomationRuleCard(state: widget.state, rule: rule),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AutomationRuleCard extends StatefulWidget {
  const _AutomationRuleCard({required this.state, required this.rule});

  final AppState state;
  final AutomationRule rule;

  @override
  State<_AutomationRuleCard> createState() => _AutomationRuleCardState();
}

class _AutomationRuleCardState extends State<_AutomationRuleCard> {
  @override
  Widget build(BuildContext context) {
    final s = widget.state.strings;
    final definition = widget.state.definitionForKey(widget.rule.key);
    final schedule = _ScheduleDraft.fromSchedule(widget.rule.schedule);
    final running = widget.state.isAutomationRuleActive(widget.rule.id);
    final label = s.automationNameLabel(
      widget.rule.key,
      fallback: definition?.name ?? widget.rule.name,
    );
    final triggerType = widget.rule.triggerType;
    final trigger =
        (widget.rule.params['trigger'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.35),
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: StartTrailingRow(
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  textAlign: TextAlign.start,
                  style: AppTypography.noteBodyStyle.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _triggerSummary(s, triggerType, schedule, trigger),
                  textAlign: TextAlign.start,
                  style: AppTypography.metaStyle.copyWith(
                    color: AppColors.textHint,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Tooltip(
                      message: s['runNow'],
                      child: IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        onPressed: running ? null : _runNow,
                        icon: running
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.primary.withValues(
                                    alpha: 0.8,
                                  ),
                                ),
                              )
                            : AppIcon(
                                AppIcons.runNow,
                                size: 17,
                                color: AppColors.primary,
                              ),
                      ),
                    ),
                    Tooltip(
                      message: s['edit'],
                      child: IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        onPressed: () => _showConfigDialog(context),
                        icon: AppIcon(
                          AppIcons.edit,
                          size: 17,
                          color: AppColors.text.withValues(alpha: 0.72),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            trailing: AppSwitch(
              value: widget.rule.enabled,
              onChanged: (value) async {
                final ok = await widget.state.updateAutomationRule(
                  widget.rule,
                  enabled: value,
                );
                if (!ok && context.mounted) {
                  _showUpdateError(context);
                }
              },
            ),
          ),
        ),
      ),
    );
  }

  String _triggerSummary(
    AppStrings s,
    String triggerType,
    _ScheduleDraft schedule,
    Map<String, dynamic> trigger,
  ) {
    if (widget.rule.key == 'view_task_reset') {
      final resets = _viewResetConfigs(widget.rule.params);
      final enabledCount = resets.values
          .where((config) => config.enabled)
          .length;
      return s.taskResetScheduleSummary(enabledCount);
    }
    return switch (triggerType) {
      'event' => s['triggerByChanges'],
      'task' => _taskTriggerLabel(s, trigger),
      _ => schedule.label(s),
    };
  }

  String _taskTriggerLabel(AppStrings s, Map<String, dynamic> trigger) {
    final viewType = trigger['view_type'] as String?;
    final section = trigger['section_name'] as String?;
    if (viewType == null) return s['triggerByTask'];
    final view = s.viewLabel(viewType);
    if (section == null || section.isEmpty) return view;
    return '$view · $section';
  }

  void _showUpdateError(BuildContext context) {
    final message =
        widget.state.takeAutomationNotice() ??
        widget.state.strings['automationRunFailed'];
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showConfigDialog(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (ctx) =>
          _AutomationConfigDialog(state: widget.state, rule: widget.rule),
    );
  }

  Future<void> _runNow() async {
    final s = widget.state.strings;
    try {
      await widget.state.runAutomationRule(widget.rule);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s['automationRan'])));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s['automationRunFailed'])));
    }
  }
}

class _AutomationConfigDialog extends StatefulWidget {
  const _AutomationConfigDialog({required this.state, required this.rule});

  final AppState state;
  final AutomationRule rule;

  @override
  State<_AutomationConfigDialog> createState() =>
      _AutomationConfigDialogState();
}

class _AutomationConfigDialogState extends State<_AutomationConfigDialog> {
  AutomationRule get _rule {
    for (final rule in widget.state.automationRules) {
      if (rule.id == widget.rule.id) return rule;
    }
    return widget.rule;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) => _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final s = widget.state.strings;
    final rule = _rule;
    final definition = widget.state.definitionForKey(rule.key);
    final label = s.automationNameLabel(
      rule.key,
      fallback: definition?.name ?? rule.name,
    );
    final description = definition == null
        ? ''
        : s.automationDescriptionLabel(
            rule.key,
            fallback: definition.description,
          );
    final triggerType = rule.triggerType;
    final activations =
        definition?.activations ?? const ['schedule', 'event', 'task'];

    return AppGlassDialog(
      title: Text(label, textAlign: TextAlign.center),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s['ok']),
        ),
      ],
      child: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (definition != null) ...[
              Text(
                s.automationScopeForDefinition(definition.scopeFixed),
                style: AppTypography.metaStyle,
                textAlign: TextAlign.start,
              ),
              if (description.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  description,
                  style: AppTypography.metaStyle.copyWith(
                    color: AppColors.text.withValues(alpha: 0.65),
                  ),
                  textAlign: TextAlign.start,
                ),
              ],
              const SizedBox(height: 12),
            ],
            Text(
              s['automationTrigger'],
              style: AppTypography.metaStyle,
              textAlign: TextAlign.start,
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.center,
              child: IntrinsicWidth(
                child: SegmentedButton<String>(
                  style: SegmentedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: AppTypography.metaStyle,
                  ),
                  segments: [
                    if (activations.contains('schedule'))
                      ButtonSegment(
                        value: 'schedule',
                        label: Text(s['triggerByTime']),
                      ),
                    if (activations.contains('event'))
                      ButtonSegment(
                        value: 'event',
                        label: Text(s['triggerByChanges']),
                      ),
                    if (activations.contains('task'))
                      ButtonSegment(
                        value: 'task',
                        label: Text(s['triggerByTask']),
                      ),
                  ],
                  selected: {triggerType},
                  onSelectionChanged: (value) => _setTriggerType(value.first),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (triggerType == 'schedule')
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (rule.key == 'view_task_reset')
                    _ViewResetFields(state: widget.state, rule: rule)
                  else
                    _ScheduleFields(state: widget.state, rule: rule),
                ],
              )
            else if (triggerType == 'event')
              Text(
                s['triggerByChanges'],
                style: AppTypography.noteBodyStyle,
                textAlign: TextAlign.start,
              )
            else
              _TaskTriggerFields(state: widget.state, rule: rule),
          ],
        ),
      ),
    );
  }

  Future<void> _setTriggerType(String triggerType) async {
    final rule = _rule;
    final definition = widget.state.definitionForKey(rule.key);
    if (definition != null && !definition.supportsActivation(triggerType)) {
      return;
    }
    final params = Map<String, dynamic>.from(rule.params);
    if (triggerType == 'task') {
      final trigger = Map<String, dynamic>.from(
        (params['trigger'] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{},
      );
      trigger.putIfAbsent('view_type', () => 'weekly');
      params['trigger'] = trigger;
      params['version'] = 2;
    }
    final ok = await widget.state.updateAutomationRule(
      rule,
      triggerType: triggerType,
      params: params,
    );
    if (!ok && mounted) {
      _showUpdateError(context);
    }
  }

  void _showUpdateError(BuildContext context) {
    final message =
        widget.state.takeAutomationNotice() ??
        widget.state.strings['automationRunFailed'];
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ScheduleFields extends StatefulWidget {
  const _ScheduleFields({required this.state, required this.rule});

  final AppState state;
  final AutomationRule rule;

  @override
  State<_ScheduleFields> createState() => _ScheduleFieldsState();
}

class _ScheduleFieldsState extends State<_ScheduleFields> {
  late _ScheduleDraft _draft;

  @override
  void initState() {
    super.initState();
    _draft = _ScheduleDraft.fromSchedule(widget.rule.schedule);
  }

  @override
  void didUpdateWidget(covariant _ScheduleFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rule.id != widget.rule.id ||
        oldWidget.rule.schedule != widget.rule.schedule) {
      _draft = _ScheduleDraft.fromSchedule(widget.rule.schedule);
    }
  }

  Future<void> _saveSchedule() async {
    final ok = await widget.state.updateAutomationRule(
      widget.rule,
      schedule: _draft.toSchedule(),
    );
    if (!ok && mounted) {
      final message =
          widget.state.takeAutomationNotice() ??
          widget.state.strings['automationRunFailed'];
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state.strings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          s['editTime'],
          style: AppTypography.metaStyle,
          textAlign: TextAlign.start,
        ),
        const SizedBox(height: 8),
        _compactDropdown(
          width: 150,
          child: DropdownButtonFormField<_ScheduleFrequency>(
            initialValue: _draft.frequency,
            decoration: _automationFieldDecoration(s['frequency']),
            dropdownColor: _automationDropdownColor(),
            borderRadius: _automationDropdownRadius(),
            elevation: 6,
            menuMaxHeight: 280,
            itemHeight: null,
            style: _automationDropdownTextStyle(),
            items: [
              DropdownMenuItem(
                value: _ScheduleFrequency.daily,
                child: _automationDropdownItem(s['onceADay']),
              ),
              DropdownMenuItem(
                value: _ScheduleFrequency.weekly,
                child: _automationDropdownItem(s['onceAWeek']),
              ),
              DropdownMenuItem(
                value: _ScheduleFrequency.monthly,
                child: _automationDropdownItem(s['onceAMonth']),
              ),
            ],
            onChanged: (value) async {
              if (value == null) return;
              setState(() => _draft = _draft.copyWith(frequency: value));
              await _saveSchedule();
            },
          ),
        ),
        const SizedBox(height: 10),
        if (_draft.frequency == _ScheduleFrequency.weekly) ...[
          _WeekdayDropdown(
            state: widget.state,
            weekday: _draft.weekday,
            onChanged: (weekday) async {
              setState(() => _draft = _draft.copyWith(weekday: weekday));
              await _saveSchedule();
            },
          ),
          const SizedBox(height: 10),
        ],
        if (_draft.frequency == _ScheduleFrequency.monthly) ...[
          _MonthPatternPicker(
            state: widget.state,
            placement: _draft.monthPlacement,
            weekday: _draft.weekday,
            onChanged: (placement, weekday) async {
              setState(
                () => _draft = _draft.copyWith(
                  monthPlacement: placement,
                  weekday: weekday,
                ),
              );
              await _saveSchedule();
            },
          ),
          const SizedBox(height: 10),
        ],
        _TimeDigitsField(
          label: s['time'],
          time: _draft.time,
          onChanged: (time) async {
            setState(() => _draft = _draft.copyWith(time: time));
            await _saveSchedule();
          },
        ),
      ],
    );
  }
}

class _ViewResetFields extends StatefulWidget {
  const _ViewResetFields({required this.state, required this.rule});

  final AppState state;
  final AutomationRule rule;

  @override
  State<_ViewResetFields> createState() => _ViewResetFieldsState();
}

class _ViewResetFieldsState extends State<_ViewResetFields> {
  late Map<String, _ViewResetConfig> _configs;

  @override
  void initState() {
    super.initState();
    _configs = _viewResetConfigs(widget.rule.params);
  }

  @override
  void didUpdateWidget(covariant _ViewResetFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rule.id != widget.rule.id ||
        oldWidget.rule.params != widget.rule.params) {
      _configs = _viewResetConfigs(widget.rule.params);
    }
  }

  Future<void> _save() async {
    final params = Map<String, dynamic>.from(widget.rule.params);
    params['version'] = 2;
    params['target_view'] = 'weekly';
    params['view_resets'] = {
      for (final entry in _configs.entries) entry.key: entry.value.toJson(),
    };
    final ok = await widget.state.updateAutomationRule(
      widget.rule,
      triggerType: 'schedule',
      params: params,
    );
    if (!ok && mounted) {
      final message =
          widget.state.takeAutomationNotice() ??
          widget.state.strings['automationRunFailed'];
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _updateConfig(
    String viewType,
    _ViewResetConfig Function(_ViewResetConfig config) update,
  ) async {
    setState(() {
      final next = Map<String, _ViewResetConfig>.from(_configs);
      next[viewType] = update(
        next[viewType] ?? _defaultViewResetConfig(viewType),
      );
      if (viewType == 'monthly') {
        final quarterly = next['quarterly'];
        if (quarterly != null && quarterly.syncWithMonthly) {
          next['quarterly'] = quarterly.copyWith(
            schedule: _quarterlyScheduleFromMonthly(
              next['monthly']!.schedule,
              quarterly.intervalMonths,
            ),
          );
        }
      }
      _configs = next;
    });
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state.strings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          s['automationResetGroupedHelp'],
          style: AppTypography.metaStyle,
          textAlign: TextAlign.start,
        ),
        const SizedBox(height: 8),
        for (final viewType in _viewResetViewTypes) ...[
          _ViewResetScheduleCard(
            state: widget.state,
            viewType: viewType,
            config: _configs[viewType] ?? _defaultViewResetConfig(viewType),
            monthlyConfig:
                _configs['monthly'] ?? _defaultViewResetConfig('monthly'),
            onChanged: (update) => _updateConfig(viewType, update),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _ViewResetScheduleCard extends StatelessWidget {
  const _ViewResetScheduleCard({
    required this.state,
    required this.viewType,
    required this.config,
    required this.monthlyConfig,
    required this.onChanged,
  });

  final AppState state;
  final String viewType;
  final _ViewResetConfig config;
  final _ViewResetConfig monthlyConfig;
  final Future<void> Function(
    _ViewResetConfig Function(_ViewResetConfig config) update,
  )
  onChanged;

  @override
  Widget build(BuildContext context) {
    final s = state.strings;
    final draft = config.schedule;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.mainNoteTop.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.noteBorder.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  state.viewLabel(viewType),
                  style: AppTypography.metaStyle,
                  textAlign: TextAlign.start,
                ),
              ),
              AppSwitch(
                value: config.enabled,
                onChanged: (value) =>
                    onChanged((current) => current.copyWith(enabled: value)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (viewType == 'quarterly') ...[
            Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: SizedBox(
                      width: 190,
                      child: DropdownButtonFormField<int>(
                        initialValue: config.intervalMonths,
                        decoration: _automationFieldDecoration(
                          s['automationResetQuarterlyInterval'],
                        ),
                        dropdownColor: _automationDropdownColor(),
                        borderRadius: _automationDropdownRadius(),
                        elevation: 6,
                        menuMaxHeight: 280,
                        itemHeight: null,
                        style: _automationDropdownTextStyle(),
                        items: [
                          DropdownMenuItem(
                            value: 3,
                            child: _automationDropdownItem(
                              s['automationResetEvery3Months'],
                            ),
                          ),
                          DropdownMenuItem(
                            value: 4,
                            child: _automationDropdownItem(
                              s['automationResetEvery4Months'],
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          onChanged(
                            (current) => current.copyWith(
                              intervalMonths: value,
                              schedule: current.syncWithMonthly
                                  ? _quarterlyScheduleFromMonthly(
                                      monthlyConfig.schedule,
                                      value,
                                    )
                                  : current.schedule.copyWith(
                                      frequency: _ScheduleFrequency.quarterly,
                                      intervalMonths: value,
                                    ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Row(
                    children: [
                      AppSwitch(
                        value: config.syncWithMonthly,
                        onChanged: (value) => onChanged(
                          (current) => current.copyWith(
                            syncWithMonthly: value,
                            schedule: value
                                ? _quarterlyScheduleFromMonthly(
                                    monthlyConfig.schedule,
                                    current.intervalMonths,
                                  )
                                : current.schedule,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          s['automationResetSyncMonthly'],
                          style: AppTypography.metaStyle,
                          textAlign: TextAlign.start,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          if (viewType != 'daily') ...[
            if (viewType == 'weekly') ...[
              _WeekdayDropdown(
                state: state,
                weekday: draft.weekday,
                onChanged: (weekday) => onChanged(
                  (current) => current.copyWith(
                    schedule: current.schedule.copyWith(weekday: weekday),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ] else if (viewType == 'monthly' ||
                (viewType == 'quarterly' && !config.syncWithMonthly)) ...[
              _MonthPatternPicker(
                state: state,
                placement: draft.monthPlacement,
                weekday: draft.weekday,
                onChanged: (placement, weekday) => onChanged(
                  (current) => current.copyWith(
                    schedule: current.schedule.copyWith(
                      monthPlacement: placement,
                      weekday: weekday,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ],
          if (viewType == 'quarterly' && config.syncWithMonthly)
            Text(
              s['automationResetSyncedMonthlyTime'],
              style: AppTypography.metaStyle.copyWith(
                color: AppColors.textHint,
              ),
              textAlign: TextAlign.start,
            )
          else
            _TimeField(
              state: state,
              viewType: viewType,
              time: draft.time,
              onChanged: (time) => onChanged(
                (current) => current.copyWith(
                  schedule: current.schedule.copyWith(time: time),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _WeekdayDropdown extends StatelessWidget {
  const _WeekdayDropdown({
    required this.state,
    required this.weekday,
    required this.onChanged,
  });

  final AppState state;
  final String weekday;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = state.strings;
    return _compactDropdown(
      width: 132,
      child: DropdownButtonFormField<String>(
        initialValue: weekday,
        decoration: _automationFieldDecoration(s['dayOfWeek']),
        dropdownColor: _automationDropdownColor(),
        borderRadius: _automationDropdownRadius(),
        elevation: 6,
        menuMaxHeight: 280,
        itemHeight: null,
        style: _automationDropdownTextStyle(),
        items: [
          for (final value in _weekdayKeys)
            DropdownMenuItem(
              value: value,
              child: _automationDropdownItem(_weekdayLabel(s, value)),
            ),
        ],
        onChanged: (value) {
          if (value == null) return;
          onChanged(value);
        },
      ),
    );
  }
}

class _MonthPatternPicker extends StatelessWidget {
  const _MonthPatternPicker({
    required this.state,
    required this.placement,
    required this.weekday,
    required this.onChanged,
  });

  final AppState state;
  final String placement;
  final String weekday;
  final void Function(String placement, String weekday) onChanged;

  @override
  Widget build(BuildContext context) {
    final s = state.strings;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            _monthPatternLabel(s, placement, weekday),
            style: AppTypography.metaStyle,
            textAlign: TextAlign.start,
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          icon: const AppIcon(
            AppIcons.calendar,
            size: 18,
            color: AppColors.primary,
          ),
          onPressed: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _initialDateForMonthPattern(placement, weekday),
              firstDate: DateTime(2020),
              lastDate: DateTime(2100),
            );
            if (picked == null) return;
            onChanged(_placementKeyForDate(picked), _weekdayKeyForDate(picked));
          },
        ),
        const SizedBox(width: 56),
      ],
    );
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.state,
    required this.viewType,
    required this.time,
    required this.onChanged,
  });

  final AppState state;
  final String viewType;
  final String time;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = state.strings;
    return _TimeDigitsField(
      key: ValueKey('reset-$viewType'),
      label: s['time'],
      time: time,
      onChanged: (value) {
        onChanged(value);
      },
    );
  }
}

class _TimeDigitsField extends StatefulWidget {
  const _TimeDigitsField({
    super.key,
    required this.label,
    required this.time,
    required this.onChanged,
  });

  final String label;
  final String time;
  final ValueChanged<String> onChanged;

  @override
  State<_TimeDigitsField> createState() => _TimeDigitsFieldState();
}

class _TimeDigitsFieldState extends State<_TimeDigitsField> {
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;
  late List<String> _digits;

  @override
  void initState() {
    super.initState();
    _digits = _digitsFromTime(widget.time);
    _controllers = [
      for (final digit in _digits) TextEditingController(text: digit),
    ];
    _focusNodes = [for (var i = 0; i < 4; i++) FocusNode()];
    for (var i = 0; i < _focusNodes.length; i++) {
      final index = i;
      _focusNodes[index].addListener(() {
        if (!_focusNodes[index].hasFocus) return;
        _controllers[index].selection = TextSelection(
          baseOffset: 0,
          extentOffset: _controllers[index].text.length,
        );
      });
    }
  }

  @override
  void didUpdateWidget(covariant _TimeDigitsField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.time == widget.time) return;
    final next = _digitsFromTime(widget.time);
    if (_digits.join() == next.join()) return;
    _digits = next;
    for (var i = 0; i < _controllers.length; i++) {
      _controllers[i].text = _digits[i];
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final focusNode in _focusNodes) {
      focusNode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(widget.label, style: AppTypography.metaStyle),
        const SizedBox(height: 6),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _digitBox(0),
              const SizedBox(width: 2),
              _digitBox(1),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  ':',
                  style: AppTypography.noteBodyStyle.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _digitBox(2),
              const SizedBox(width: 2),
              _digitBox(3),
            ],
          ),
        ),
      ],
    );
  }

  Widget _digitBox(int index) {
    return SizedBox(
      width: 24,
      height: 30,
      child: TextField(
        controller: _controllers[index],
        focusNode: _focusNodes[index],
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: AppTypography.noteBodyStyle.copyWith(
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          isDense: true,
          counterText: '',
          contentPadding: const EdgeInsets.symmetric(vertical: 6),
          enabledBorder: _timeDigitBorder(
            AppColors.noteBorder.withValues(alpha: 0.68),
          ),
          focusedBorder: _timeDigitBorder(
            AppColors.primary.withValues(alpha: 0.54),
          ),
          border: _timeDigitBorder(AppColors.noteBorder),
        ),
        onTap: () => _controllers[index].selection = TextSelection(
          baseOffset: 0,
          extentOffset: _controllers[index].text.length,
        ),
        onChanged: (value) => _setDigit(index, value),
      ),
    );
  }

  OutlineInputBorder _timeDigitBorder(Color color) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: color, width: 0.85),
    );
  }

  void _setDigit(int index, String value) {
    if (value.isEmpty) return;
    _digits[index] = value.substring(value.length - 1);
    _normalizeDigitsAfter(index);

    for (var i = 0; i < _controllers.length; i++) {
      _controllers[i].value = TextEditingValue(
        text: _digits[i],
        selection: const TextSelection.collapsed(offset: 1),
      );
    }

    if (index < _focusNodes.length - 1) {
      _focusNodes[index + 1].requestFocus();
      _controllers[index + 1].selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controllers[index + 1].text.length,
      );
    } else {
      _focusNodes[index].unfocus();
    }
    widget.onChanged('${_digits[0]}${_digits[1]}:${_digits[2]}${_digits[3]}');
  }

  void _normalizeDigitsAfter(int editedIndex) {
    final hourTens = int.tryParse(_digits[0]) ?? 0;
    var hourOnes = int.tryParse(_digits[1]) ?? 0;
    var minuteTens = int.tryParse(_digits[2]) ?? 0;

    if (hourTens > 2) {
      _digits[0] = '2';
    }
    if ((int.tryParse(_digits[0]) ?? 0) == 2 && hourOnes > 3) {
      hourOnes = 3;
      _digits[1] = '3';
    }
    if (minuteTens > 5) {
      minuteTens = 5;
      _digits[2] = '5';
    }

    if (editedIndex == 0 && (int.tryParse(_digits[0]) ?? 0) == 2) {
      final nextHourOnes = int.tryParse(_digits[1]) ?? 0;
      if (nextHourOnes > 3) {
        _digits[1] = '3';
      }
    }
  }
}

List<String> _digitsFromTime(String time) {
  final normalized = _normalizeTime(time);
  return [normalized[0], normalized[1], normalized[3], normalized[4]];
}

class _TaskTriggerFields extends StatefulWidget {
  const _TaskTriggerFields({required this.state, required this.rule});

  final AppState state;
  final AutomationRule rule;

  @override
  State<_TaskTriggerFields> createState() => _TaskTriggerFieldsState();
}

class _TaskTriggerFieldsState extends State<_TaskTriggerFields> {
  late String _viewType;
  String? _sectionName;
  List<ViewSection> _sections = [];
  var _loading = true;
  final _sectionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final trigger =
        (widget.rule.params['trigger'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    _viewType = trigger['view_type'] as String? ?? 'weekly';
    _sectionName = trigger['section_name'] as String?;
    _loadSections();
  }

  @override
  void didUpdateWidget(covariant _TaskTriggerFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rule.id != widget.rule.id ||
        oldWidget.rule.params != widget.rule.params) {
      final trigger =
          (widget.rule.params['trigger'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};
      _viewType = trigger['view_type'] as String? ?? 'weekly';
      _sectionName = trigger['section_name'] as String?;
    }
  }

  @override
  void dispose() {
    _sectionController.dispose();
    super.dispose();
  }

  Future<void> _loadSections() async {
    setState(() => _loading = true);
    final sections = await widget.state.fetchSectionsForView(_viewType);
    if (!mounted) return;
    setState(() {
      _sections = sections;
      _loading = false;
      if (_sectionName != null &&
          !sections.any((section) => section.name == _sectionName)) {
        _sectionName = sections.isEmpty ? null : sections.first.name;
      } else {
        _sectionName ??= sections.isEmpty ? null : sections.first.name;
      }
    });
  }

  Future<void> _createSection() async {
    final name = _sectionController.text.trim();
    if (name.isEmpty) return;
    await widget.state.createViewSection(_viewType, name);
    _sectionController.clear();
    if (!mounted) return;
    final sections = await widget.state.fetchSectionsForView(_viewType);
    if (!mounted) return;
    setState(() {
      _sections = sections;
      _sectionName = name;
    });
    await _save();
  }

  Future<void> _save() async {
    if (_sectionName == null || _sectionName!.isEmpty) return;
    final params = Map<String, dynamic>.from(widget.rule.params);
    final trigger = Map<String, dynamic>.from(
      (params['trigger'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{},
    );
    trigger['view_type'] = _viewType;
    trigger['section_name'] = _sectionName;
    params['version'] = 2;
    params['trigger'] = trigger;
    final companion = Map<String, dynamic>.from(
      (params['companion_task'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{},
    );
    companion.putIfAbsent('view_type', () => _viewType);
    companion.putIfAbsent('section_name', () => _sectionName);
    params['companion_task'] = companion;
    final ok = await widget.state.updateAutomationRule(
      widget.rule,
      triggerType: 'task',
      params: params,
    );
    if (!ok && mounted) {
      final message =
          widget.state.takeAutomationNotice() ??
          widget.state.strings['automationRunFailed'];
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state.strings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _compactDropdown(
          width: 140,
          child: DropdownButtonFormField<String>(
            initialValue: _viewType,
            decoration: _automationFieldDecoration(s['automationTriggerView']),
            dropdownColor: _automationDropdownColor(),
            borderRadius: _automationDropdownRadius(),
            elevation: 6,
            menuMaxHeight: 280,
            itemHeight: null,
            style: _automationDropdownTextStyle(),
            items: [
              for (final view in ViewRegistry.views)
                DropdownMenuItem(
                  value: view.type,
                  child: _automationDropdownItem(s.viewLabel(view.type)),
                ),
            ],
            onChanged: (value) async {
              if (value == null) return;
              setState(() => _viewType = value);
              await _loadSections();
              await _save();
            },
          ),
        ),
        const SizedBox(height: 10),
        if (_loading)
          const Center(child: CircularProgressIndicator(strokeWidth: 2))
        else if (_sections.isEmpty) ...[
          Text(
            s['automationTriggerSectionHelp'],
            style: AppTypography.noteBodyStyle,
            textAlign: TextAlign.start,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _sectionController,
            textAlign: TextAlign.start,
            decoration: _automationFieldDecoration(s['sectionName']),
            onSubmitted: (_) => _createSection(),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              onPressed: _createSection,
              child: Text(s['createSection']),
            ),
          ),
        ] else
          _compactDropdown(
            width: 180,
            child: DropdownButtonFormField<String>(
              initialValue: _sectionName,
              decoration: _automationFieldDecoration(
                s['automationTriggerSection'],
              ),
              dropdownColor: _automationDropdownColor(),
              borderRadius: _automationDropdownRadius(),
              elevation: 6,
              menuMaxHeight: 280,
              itemHeight: null,
              style: _automationDropdownTextStyle(),
              items: [
                for (final section in _sections)
                  DropdownMenuItem(
                    value: section.name,
                    child: _automationDropdownItem(section.name),
                  ),
              ],
              onChanged: (value) async {
                setState(() => _sectionName = value);
                await _save();
              },
            ),
          ),
      ],
    );
  }
}

const _viewResetViewTypes = ['daily', 'weekly', 'monthly', 'quarterly'];

enum _ScheduleFrequency { daily, weekly, monthly, quarterly }

class _ViewResetConfig {
  const _ViewResetConfig({
    required this.enabled,
    required this.schedule,
    this.intervalMonths = 3,
    this.syncWithMonthly = false,
  });

  final bool enabled;
  final _ScheduleDraft schedule;
  final int intervalMonths;
  final bool syncWithMonthly;

  _ViewResetConfig copyWith({
    bool? enabled,
    _ScheduleDraft? schedule,
    int? intervalMonths,
    bool? syncWithMonthly,
  }) {
    return _ViewResetConfig(
      enabled: enabled ?? this.enabled,
      schedule: schedule ?? this.schedule,
      intervalMonths: intervalMonths ?? this.intervalMonths,
      syncWithMonthly: syncWithMonthly ?? this.syncWithMonthly,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'schedule': schedule.toSchedule(),
    'interval_months': intervalMonths,
    'sync_with_monthly': syncWithMonthly,
  };
}

Map<String, _ViewResetConfig> _viewResetConfigs(Map<String, dynamic> params) {
  final rawResets = params['view_resets'];
  final result = {
    for (final viewType in _viewResetViewTypes)
      viewType: _defaultViewResetConfig(viewType),
  };
  if (rawResets is Map) {
    for (final viewType in _viewResetViewTypes) {
      final rawConfig = rawResets[viewType];
      if (rawConfig is! Map) continue;
      final defaultConfig = result[viewType]!;
      final interval = rawConfig['interval_months'] as int?;
      result[viewType] = defaultConfig.copyWith(
        enabled: rawConfig['enabled'] as bool? ?? defaultConfig.enabled,
        intervalMonths: interval == 4 ? 4 : 3,
        syncWithMonthly:
            rawConfig['sync_with_monthly'] as bool? ??
            defaultConfig.syncWithMonthly,
        schedule: _ScheduleDraft.fromSchedule(
          rawConfig['schedule'] as String? ??
              defaultConfig.schedule.toSchedule(),
        ),
      );
    }
  } else if (params['target_view'] is String) {
    final targetView = params['target_view'] as String;
    if (result.containsKey(targetView)) {
      result[targetView] = result[targetView]!.copyWith(enabled: true);
    }
  }
  return result;
}

_ViewResetConfig _defaultViewResetConfig(String viewType) {
  return switch (viewType) {
    'daily' => _ViewResetConfig(
      enabled: true,
      schedule: _ScheduleDraft.fromSchedule('daily 23:59'),
    ),
    'monthly' => _ViewResetConfig(
      enabled: true,
      schedule: _ScheduleDraft.fromSchedule('monthly last sat 23:59'),
    ),
    'quarterly' => _ViewResetConfig(
      enabled: true,
      schedule: _ScheduleDraft.fromSchedule('quarterly 3 last sat 23:59'),
      intervalMonths: 3,
      syncWithMonthly: true,
    ),
    _ => _ViewResetConfig(
      enabled: true,
      schedule: _ScheduleDraft.fromSchedule('weekly sat 23:59'),
    ),
  };
}

_ScheduleDraft _quarterlyScheduleFromMonthly(
  _ScheduleDraft monthly,
  int intervalMonths,
) {
  return monthly.copyWith(
    frequency: _ScheduleFrequency.quarterly,
    intervalMonths: intervalMonths,
  );
}

class _ScheduleDraft {
  const _ScheduleDraft({
    required this.frequency,
    required this.time,
    required this.weekday,
    required this.monthPlacement,
    this.intervalMonths = 3,
  });

  factory _ScheduleDraft.fromSchedule(String schedule) {
    final parts = schedule.trim().toLowerCase().split(RegExp(r'\s+'));
    if (parts.isEmpty) return _default;

    if (parts.first == 'weekly') {
      return _ScheduleDraft(
        frequency: _ScheduleFrequency.weekly,
        weekday: _normalizeWeekday(parts.length > 1 ? parts[1] : 'mon'),
        time: _normalizeTime(parts.length > 2 ? parts[2] : '00:00'),
        monthPlacement: 'first',
      );
    }

    if (parts.first == 'monthly') {
      return _ScheduleDraft(
        frequency: _ScheduleFrequency.monthly,
        monthPlacement: _normalizePlacement(
          parts.length > 1 ? parts[1] : 'first',
        ),
        weekday: _normalizeWeekday(parts.length > 2 ? parts[2] : 'mon'),
        time: _normalizeTime(parts.length > 3 ? parts[3] : '00:00'),
      );
    }

    if (parts.first == 'quarterly') {
      final interval = int.tryParse(parts.length > 1 ? parts[1] : '3');
      return _ScheduleDraft(
        frequency: _ScheduleFrequency.quarterly,
        intervalMonths: interval == 4 ? 4 : 3,
        monthPlacement: _normalizePlacement(
          parts.length > 2 ? parts[2] : 'first',
        ),
        weekday: _normalizeWeekday(parts.length > 3 ? parts[3] : 'mon'),
        time: _normalizeTime(parts.length > 4 ? parts[4] : '00:00'),
      );
    }

    return _ScheduleDraft(
      frequency: _ScheduleFrequency.daily,
      weekday: 'mon',
      time: _normalizeTime(parts.length > 1 ? parts[1] : '00:00'),
      monthPlacement: 'first',
    );
  }

  static const _default = _ScheduleDraft(
    frequency: _ScheduleFrequency.daily,
    time: '00:00',
    weekday: 'mon',
    monthPlacement: 'first',
    intervalMonths: 3,
  );

  final _ScheduleFrequency frequency;
  final String time;
  final String weekday;
  final String monthPlacement;
  final int intervalMonths;

  _ScheduleDraft copyWith({
    _ScheduleFrequency? frequency,
    String? time,
    String? weekday,
    String? monthPlacement,
    int? intervalMonths,
  }) {
    return _ScheduleDraft(
      frequency: frequency ?? this.frequency,
      time: time ?? this.time,
      weekday: weekday ?? this.weekday,
      monthPlacement: monthPlacement ?? this.monthPlacement,
      intervalMonths: intervalMonths ?? this.intervalMonths,
    );
  }

  String toSchedule() {
    return switch (frequency) {
      _ScheduleFrequency.daily => 'daily $time',
      _ScheduleFrequency.weekly => 'weekly $weekday $time',
      _ScheduleFrequency.monthly => 'monthly $monthPlacement $weekday $time',
      _ScheduleFrequency.quarterly =>
        'quarterly $intervalMonths $monthPlacement $weekday $time',
    };
  }

  String label(AppStrings s) {
    return switch (frequency) {
      _ScheduleFrequency.daily => '${s['onceADay']}, $time',
      _ScheduleFrequency.weekly =>
        '${s['onceAWeek']}, ${_weekdayLabel(s, weekday)}, $time',
      _ScheduleFrequency.monthly =>
        '${s['onceAMonth']}, ${_placementLabel(s, monthPlacement)} ${_weekdayLabel(s, weekday)}, $time',
      _ScheduleFrequency.quarterly =>
        '${s['automationResetQuarterly']}, ${_placementLabel(s, monthPlacement)} ${_weekdayLabel(s, weekday)}, $time',
    };
  }
}

String _normalizeTime(String value) {
  return _tryNormalizeTime(value) ?? '00:00';
}

String? _tryNormalizeTime(String value) {
  final parts = value.split(':');
  if (parts.length != 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
  return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

String _normalizeWeekday(String value) {
  return switch (value) {
    'monday' || 'mon' => 'mon',
    'tuesday' || 'tue' => 'tue',
    'wednesday' || 'wed' => 'wed',
    'thursday' || 'thu' => 'thu',
    'friday' || 'fri' => 'fri',
    'saturday' || 'sat' => 'sat',
    'sunday' || 'sun' => 'sun',
    _ => 'mon',
  };
}

String _normalizePlacement(String value) {
  return switch (value) {
    'first' || 'second' || 'third' || 'last' => value,
    _ => 'first',
  };
}

String _weekdayLabel(AppStrings s, String weekday) {
  return switch (weekday) {
    'mon' => s['monday'],
    'tue' => s['tuesday'],
    'wed' => s['wednesday'],
    'thu' => s['thursday'],
    'fri' => s['friday'],
    'sat' => s['saturday'],
    'sun' => s['sunday'],
    _ => s['monday'],
  };
}

String _placementLabel(AppStrings s, String placement) {
  return switch (placement) {
    'first' => s['first'],
    'second' => s['second'],
    'third' => s['third'],
    'last' => s['last'],
    _ => s['first'],
  };
}

String _monthPatternLabel(AppStrings s, String placement, String weekday) {
  final weekdayLabel = _weekdayLabel(s, weekday);
  final placementLabel = _placementLabel(s, placement);
  if (s.isRtl) {
    return 'יום $weekdayLabel, בשבוע ה$placementLabel בחודש';
  }
  return '$weekdayLabel on the $placementLabel of the month';
}

const _weekdayKeys = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

String _weekdayKeyForDate(DateTime date) {
  return switch (date.weekday) {
    DateTime.monday => 'mon',
    DateTime.tuesday => 'tue',
    DateTime.wednesday => 'wed',
    DateTime.thursday => 'thu',
    DateTime.friday => 'fri',
    DateTime.saturday => 'sat',
    DateTime.sunday => 'sun',
    _ => 'mon',
  };
}

String _placementKeyForDate(DateTime date) {
  if (date.add(const Duration(days: 7)).month != date.month) {
    return 'last';
  }
  final occurrence = ((date.day - 1) ~/ 7) + 1;
  return switch (occurrence) {
    1 => 'first',
    2 => 'second',
    3 => 'third',
    _ => 'last',
  };
}

DateTime _initialDateForMonthPattern(String placement, String weekday) {
  final now = DateTime.now();
  final targetWeekday = _weekdayNumber(weekday);
  final firstOfMonth = DateTime(now.year, now.month);
  final firstDelta = (targetWeekday - firstOfMonth.weekday) % 7;
  final firstMatch = firstOfMonth.add(Duration(days: firstDelta));

  if (placement == 'last') {
    final lastOfMonth = DateTime(now.year, now.month + 1, 0);
    final backDelta = (lastOfMonth.weekday - targetWeekday) % 7;
    return lastOfMonth.subtract(Duration(days: backDelta));
  }

  final offset = switch (placement) {
    'second' => 7,
    'third' => 14,
    _ => 0,
  };
  return firstMatch.add(Duration(days: offset));
}

int _weekdayNumber(String weekday) {
  return switch (weekday) {
    'mon' => DateTime.monday,
    'tue' => DateTime.tuesday,
    'wed' => DateTime.wednesday,
    'thu' => DateTime.thursday,
    'fri' => DateTime.friday,
    'sat' => DateTime.saturday,
    'sun' => DateTime.sunday,
    _ => DateTime.monday,
  };
}
