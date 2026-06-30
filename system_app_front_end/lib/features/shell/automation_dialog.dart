import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/models/automation_rule.dart';
import '../../core/models/view_section.dart';
import '../../core/registry/view_registry.dart';
import '../../design_system/app_typography.dart';
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
  static const _mainKeys = {'daily_rotation', 'weekly_process_refresh'};

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
        final rules = widget.state.automationRules
            .where((rule) => _mainKeys.contains(rule.key))
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s['mainAutomations'], style: AppTypography.metaStyle),
                const SizedBox(height: 10),
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
                  Text(s['noAutomations'], style: AppTypography.noteBodyStyle)
                else
                  for (final rule in rules)
                    _AutomationRuleControl(state: widget.state, rule: rule),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AutomationRuleControl extends StatefulWidget {
  const _AutomationRuleControl({required this.state, required this.rule});

  final AppState state;
  final AutomationRule rule;

  @override
  State<_AutomationRuleControl> createState() => _AutomationRuleControlState();
}

class _AutomationRuleControlState extends State<_AutomationRuleControl> {
  @override
  Widget build(BuildContext context) {
    final s = widget.state.strings;
    final schedule = _ScheduleDraft.fromSchedule(widget.rule.schedule);
    final running = widget.state.isAutomationRuleActive(widget.rule.id);
    final label = switch (widget.rule.key) {
      'daily_rotation' => s['dailyRotation'],
      'weekly_process_refresh' => s['updateAllProcesses'],
      _ => widget.rule.name,
    };
    final triggerType = widget.rule.triggerType;
    final trigger = (widget.rule.params['trigger'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(label, style: AppTypography.noteBodyStyle),
                subtitle: Text(
                  _triggerSummary(s, triggerType, schedule, trigger),
                  style: AppTypography.metaStyle,
                ),
                value: widget.rule.enabled,
                onChanged: (value) => widget.state.updateAutomationRule(
                  widget.rule,
                  enabled: value,
                ),
              ),
              Text(s['automationTrigger'], style: AppTypography.metaStyle),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'schedule', label: Text(s['triggerByTime'])),
                  ButtonSegment(value: 'event', label: Text(s['triggerByChanges'])),
                  ButtonSegment(value: 'task', label: Text(s['triggerByTask'])),
                ],
                selected: {triggerType},
                onSelectionChanged: (value) => _setTriggerType(value.first),
              ),
              const SizedBox(height: 8),
              if (triggerType == 'schedule') ...[
                Row(
                  children: [
                    TextButton(
                      onPressed: () => _showScheduleDialog(context),
                      child: Text(s['editTime']),
                    ),
                  ],
                ),
              ] else if (triggerType == 'event') ...[
                Text(
                  s['triggerByChanges'],
                  style: AppTypography.noteBodyStyle,
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _taskTriggerLabel(s, trigger),
                        style: AppTypography.noteBodyStyle,
                      ),
                    ),
                    TextButton(
                      onPressed: () => _showTaskTriggerDialog(context),
                      child: Text(s['edit']),
                    ),
                  ],
                ),
              ],
              Row(
                children: [
                  if (triggerType == 'schedule') const Spacer(),
                  TextButton(
                    onPressed: running ? null : _runNow,
                    child: running
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              const SizedBox(width: 8),
                              Text(s['automationRunning']),
                            ],
                          )
                        : Text(s['runNow']),
                  ),
                ],
              ),
            ],
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

  Future<void> _setTriggerType(String triggerType) async {
    final params = Map<String, dynamic>.from(widget.rule.params);
    if (triggerType == 'task') {
      final trigger = Map<String, dynamic>.from(
        (params['trigger'] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{},
      );
      trigger.putIfAbsent('view_type', () => 'weekly');
      params['trigger'] = trigger;
      params['version'] = 2;
    }
    await widget.state.updateAutomationRule(
      widget.rule,
      triggerType: triggerType,
      params: params,
    );
  }

  Future<void> _showTaskTriggerDialog(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => _TaskTriggerDialog(
        state: widget.state,
        rule: widget.rule,
      ),
    );
  }

  Future<void> _showScheduleDialog(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => _ScheduleDialog(state: widget.state, rule: widget.rule),
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

class _ScheduleDialog extends StatefulWidget {
  const _ScheduleDialog({required this.state, required this.rule});

  final AppState state;
  final AutomationRule rule;

  @override
  State<_ScheduleDialog> createState() => _ScheduleDialogState();
}

class _ScheduleDialogState extends State<_ScheduleDialog> {
  late _ScheduleDraft _draft;

  @override
  void initState() {
    super.initState();
    _draft = _ScheduleDraft.fromSchedule(widget.rule.schedule);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state.strings;

    return AppGlassDialog(
      title: Text(s['editTime']),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s['cancel']),
        ),
        TextButton(onPressed: _save, child: Text(s['save'])),
      ],
      child: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<_ScheduleFrequency>(
              initialValue: _draft.frequency,
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
              onChanged: (value) {
                if (value == null) return;
                setState(() => _draft = _draft.copyWith(frequency: value));
              },
            ),
            const SizedBox(height: 10),
            if (_draft.frequency != _ScheduleFrequency.daily) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${s['dayOfWeek']}: ${_weekdayLabel(s, _draft.weekday)}',
                      style: AppTypography.metaStyle,
                    ),
                  ),
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
                initialValue: _draft.monthPlacement,
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
                onChanged: (value) {
                  if (value == null) return;
                  setState(
                    () => _draft = _draft.copyWith(monthPlacement: value),
                  );
                },
              ),
              const SizedBox(height: 10),
            ],
            TextFormField(
              key: ValueKey('${widget.rule.id}-${_draft.time}'),
              initialValue: _draft.time,
              style: AppTypography.noteBodyStyle,
              decoration: InputDecoration(
                isDense: true,
                labelText: s['time'],
                helperText: s['automationTimeHelp'],
              ),
              onChanged: _updateTime,
            ),
          ],
        ),
      ),
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
  }

  void _updateTime(String value) {
    final normalized = _tryNormalizeTime(value.trim());
    if (normalized == null) return;
    setState(() => _draft = _draft.copyWith(time: normalized));
  }

  Future<void> _save() async {
    await widget.state.updateAutomationRule(
      widget.rule,
      schedule: _draft.toSchedule(),
    );
    if (mounted) Navigator.pop(context);
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

class _TaskTriggerDialog extends StatefulWidget {
  const _TaskTriggerDialog({required this.state, required this.rule});

  final AppState state;
  final AutomationRule rule;

  @override
  State<_TaskTriggerDialog> createState() => _TaskTriggerDialogState();
}

class _TaskTriggerDialogState extends State<_TaskTriggerDialog> {
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
    await widget.state.updateAutomationRule(
      widget.rule,
      triggerType: 'task',
      params: params,
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state.strings;

    return AppGlassDialog(
      title: Text(s['triggerByTask']),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s['cancel']),
        ),
        FilledButton(
          onPressed: _sectionName == null ? null : _save,
          child: Text(s['save']),
        ),
      ],
      child: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _viewType,
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
              onChanged: (value) {
                if (value == null) return;
                setState(() => _viewType = value);
                _loadSections();
              },
            ),
            const SizedBox(height: 10),
            if (_loading)
              const Center(child: CircularProgressIndicator(strokeWidth: 2))
            else if (_sections.isEmpty) ...[
              Text(
                s['automationTriggerSectionHelp'],
                style: AppTypography.noteBodyStyle,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _sectionController,
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
                initialValue: _sectionName,
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
                onChanged: (value) => setState(() => _sectionName = value),
              ),
          ],
        ),
      ),
    );
  }
}
