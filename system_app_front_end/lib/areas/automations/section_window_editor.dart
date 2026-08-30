import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_state.dart';
import '../ui/adaptive_dialog.dart';
import '../ui/app_segmented_toggle.dart';
import '../ui/compact_calendar.dart';
import '../ui/dialog_field_style.dart';
import '../ui/time_picker_dialog.dart';
import './automation.dart';
import './schedule_format.dart';

Future<bool> showSectionWindowEditor({
  required BuildContext context,
  required AppState state,
  required Automation automation,
}) async {
  final saved = await showAppDialog<bool>(
    context: context,
    builder: (ctx) => _SectionWindowEditor(
      state: state,
      automation: automation,
    ),
  );
  return saved ?? false;
}

class _SectionWindowEditor extends StatefulWidget {
  const _SectionWindowEditor({
    required this.state,
    required this.automation,
  });

  final AppState state;
  final Automation automation;

  @override
  State<_SectionWindowEditor> createState() => _SectionWindowEditorState();
}

class _SectionWindowEditorState extends State<_SectionWindowEditor> {
  late AutomationSchedule _schedule;
  late final TextEditingController _hours;
  late final TextEditingController _minutes;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _schedule = AutomationSchedule.parse(widget.automation.schedule);
    final total = widget.automation.windowDurationMinutes ?? 0;
    _hours = TextEditingController(text: '${total ~/ 60}');
    _minutes = TextEditingController(text: '${total % 60}');
  }

  @override
  void dispose() {
    _hours.dispose();
    _minutes.dispose();
    super.dispose();
  }

  int? get _durationMinutes {
    final hours = int.tryParse(_hours.text.trim()) ?? 0;
    final minutes = int.tryParse(_minutes.text.trim()) ?? 0;
    final total = hours * 60 + minutes;
    return total > 0 ? total : null;
  }

  bool get _canSave => _durationMinutes != null;

  Future<void> _save() async {
    final duration = _durationMinutes;
    if (duration == null) return;
    setState(() => _saving = true);
    try {
      await widget.state.updateAutomation(widget.automation, {
        'schedule': _schedule.toDsl(),
        'timezone': AutomationSchedule.defaultTimezone,
        'window_duration_minutes': duration,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  String _whenCaption() {
    final s = widget.state.strings;
    final dayKey = AutomationSchedule.weekdayKeys[_schedule.weekday]!;
    if (_schedule.kind == 'weekly') return s.weeklyScheduleCaption(dayKey);
    if (_schedule.kind == 'monthly') {
      return s.monthlyScheduleCaption(_schedule.placement, dayKey);
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state.strings;
    final time = AppCompactTimePicker(
      title: s['time'],
      value: timeOfDayFromHmm(_schedule.time),
      onChanged: (picked) {
        setState(
          () => _schedule = _schedule.copyWith(time: hmmFromTimeOfDay(picked)),
        );
      },
    );

    return AppAdaptiveDialogShell(
      title: Text(widget.state.automationDisplayName(widget.automation)),
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
          AppDialogChoiceField<String>(
            label: s['schedule'],
            options: [
              AppSegmentedOption(value: 'daily', label: s['onceADay']),
              AppSegmentedOption(value: 'weekly', label: s['onceAWeek']),
              AppSegmentedOption(value: 'monthly', label: s['onceAMonth']),
            ],
            selected: _schedule.kind,
            onSelected: (kind) =>
                setState(() => _schedule = _schedule.copyWith(kind: kind)),
          ),
          const SizedBox(height: DialogFieldStyle.fieldGap),
          if (_schedule.kind == 'daily')
            time
          else
            Row(
              children: [
                Expanded(
                  child: AppCompactCalendar(
                    title: s['chooseDay'],
                    weekdayLabels: s.narrowWeekdaysSundayFirst,
                    formatMonth: s.monthYear,
                    isMarked: _schedule.marksDate,
                    caption: _whenCaption(),
                    onDaySelected: (date) {
                      setState(() => _schedule = _schedule.applyingDate(date));
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: time),
              ],
            ),
          const SizedBox(height: DialogFieldStyle.fieldGap),
          AppDialogField(
            label: s['windowDuration'],
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _hours,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: DialogFieldStyle.decoration(
                      hintText: s['durationHours'],
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _minutes,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: DialogFieldStyle.decoration(
                      hintText: s['durationMinutes'],
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
