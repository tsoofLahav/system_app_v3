import 'package:flutter/material.dart';

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
    final trigger = (widget.rule.params['trigger'] as Map?)?.cast<String, dynamic>() ??
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
    final message = widget.state.takeAutomationNotice() ??
        widget.state.strings['automationRunFailed'];
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showConfigDialog(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => _AutomationConfigDialog(
        state: widget.state,
        rule: widget.rule,
      ),
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
    final activations = definition?.activations ??
        const ['schedule', 'event', 'task'];

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
              SegmentedButton<String>(
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
              const SizedBox(height: 12),
              if (triggerType == 'schedule')
                _ScheduleFields(state: widget.state, rule: rule)
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
    final message = widget.state.takeAutomationNotice() ??
        widget.state.strings['automationRunFailed'];
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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
      final message = widget.state.takeAutomationNotice() ??
          widget.state.strings['automationRunFailed'];
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
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
        DropdownButtonFormField<_ScheduleFrequency>(
          value: _draft.frequency,
          decoration: InputDecoration(
            isDense: true,
            labelText: s['frequency'],
          ),
          items: [
            DropdownMenuItem(
              value: _ScheduleFrequency.daily,
              child: Text(s['onceADay']),
            ),
            DropdownMenuItem(
              value: _ScheduleFrequency.weekly,
              child: Text(s['onceAWeek']),
            ),
            DropdownMenuItem(
              value: _ScheduleFrequency.monthly,
              child: Text(s['onceAMonth']),
            ),
          ],
          onChanged: (value) async {
            if (value == null) return;
            setState(() => _draft = _draft.copyWith(frequency: value));
            await _saveSchedule();
          },
        ),
        const SizedBox(height: 10),
        if (_draft.frequency != _ScheduleFrequency.daily) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  '${s['dayOfWeek']}: ${_weekdayLabel(s, _draft.weekday)}',
                  style: AppTypography.metaStyle,
                  textAlign: TextAlign.start,
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today_outlined, size: 16),
                label: Text(s['chooseDay']),
                onPressed: _chooseDay,
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        if (_draft.frequency == _ScheduleFrequency.monthly) ...[
          DropdownButtonFormField<String>(
            value: _draft.monthPlacement,
            decoration: InputDecoration(
              isDense: true,
              labelText: s['placementInMonth'],
            ),
            items: [
              DropdownMenuItem(value: 'first', child: Text(s['first'])),
              DropdownMenuItem(value: 'second', child: Text(s['second'])),
              DropdownMenuItem(value: 'third', child: Text(s['third'])),
              DropdownMenuItem(value: 'last', child: Text(s['last'])),
            ],
            onChanged: (value) async {
              if (value == null) return;
              setState(() => _draft = _draft.copyWith(monthPlacement: value));
              await _saveSchedule();
            },
          ),
          const SizedBox(height: 10),
        ],
        TextFormField(
          key: ValueKey('${widget.rule.id}-${_draft.time}'),
          initialValue: _draft.time,
          style: AppTypography.noteBodyStyle,
          textAlign: TextAlign.start,
          decoration: InputDecoration(
            isDense: true,
            labelText: s['time'],
            helperText: s['automationTimeHelp'],
          ),
          onFieldSubmitted: (_) => _saveSchedule(),
          onChanged: (value) {
            final normalized = _tryNormalizeTime(value.trim());
            if (normalized == null) return;
            setState(() => _draft = _draft.copyWith(time: normalized));
          },
          onEditingComplete: _saveSchedule,
        ),
      ],
    );
  }

  Future<void> _chooseDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _initialDateForWeekday(_draft.weekday),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(
      () => _draft = _draft.copyWith(weekday: _weekdayKeyForDate(picked)),
    );
    await _saveSchedule();
  }
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
      final message = widget.state.takeAutomationNotice() ??
          widget.state.strings['automationRunFailed'];
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state.strings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          value: _viewType,
          decoration: InputDecoration(
            isDense: true,
            labelText: s['automationTriggerView'],
          ),
          items: [
            for (final view in ViewRegistry.views)
              DropdownMenuItem(
                value: view.type,
                child: Text(s.viewLabel(view.type)),
              ),
          ],
          onChanged: (value) async {
            if (value == null) return;
            setState(() => _viewType = value);
            await _loadSections();
            await _save();
          },
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
            decoration: InputDecoration(
              isDense: true,
              labelText: s['sectionName'],
            ),
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
          DropdownButtonFormField<String>(
            value: _sectionName,
            decoration: InputDecoration(
              isDense: true,
              labelText: s['automationTriggerSection'],
            ),
            items: [
              for (final section in _sections)
                DropdownMenuItem(
                  value: section.name,
                  child: Text(section.name),
                ),
            ],
            onChanged: (value) async {
              setState(() => _sectionName = value);
              await _save();
            },
          ),
      ],
    );
  }
}

enum _ScheduleFrequency { daily, weekly, monthly }

class _ScheduleDraft {
  const _ScheduleDraft({
    required this.frequency,
    required this.time,
    required this.weekday,
    required this.monthPlacement,
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
  );

  final _ScheduleFrequency frequency;
  final String time;
  final String weekday;
  final String monthPlacement;

  _ScheduleDraft copyWith({
    _ScheduleFrequency? frequency,
    String? time,
    String? weekday,
    String? monthPlacement,
  }) {
    return _ScheduleDraft(
      frequency: frequency ?? this.frequency,
      time: time ?? this.time,
      weekday: weekday ?? this.weekday,
      monthPlacement: monthPlacement ?? this.monthPlacement,
    );
  }

  String toSchedule() {
    return switch (frequency) {
      _ScheduleFrequency.daily => 'daily $time',
      _ScheduleFrequency.weekly => 'weekly $weekday $time',
      _ScheduleFrequency.monthly => 'monthly $monthPlacement $weekday $time',
    };
  }

  String label(AppStrings s) {
    return switch (frequency) {
      _ScheduleFrequency.daily => '${s['onceADay']}, $time',
      _ScheduleFrequency.weekly =>
        '${s['onceAWeek']}, ${_weekdayLabel(s, weekday)}, $time',
      _ScheduleFrequency.monthly =>
        '${s['onceAMonth']}, ${_placementLabel(s, monthPlacement)} ${_weekdayLabel(s, weekday)}, $time',
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

DateTime _initialDateForWeekday(String weekday) {
  final now = DateTime.now();
  final target = _weekdayNumber(weekday);
  final days = (target - now.weekday) % 7;
  return now.add(Duration(days: days));
}

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
