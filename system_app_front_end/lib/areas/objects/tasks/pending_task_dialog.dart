import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../ui/adaptive_dialog.dart';
import '../../ui/compact_calendar.dart';
import '../../ui/dialog_metrics.dart';

/// Pick the day a pending task should become active.
Future<DateTime?> showPendingActivateDateDialog({
  required BuildContext context,
  required AppState state,
  DateTime? initial,
}) {
  return showAppDialog<DateTime>(
    context: context,
    builder: (ctx) => _PendingActivateDateDialog(
      state: state,
      initial: initial,
    ),
  );
}

class _PendingActivateDateDialog extends StatefulWidget {
  const _PendingActivateDateDialog({required this.state, this.initial});

  final AppState state;
  final DateTime? initial;

  @override
  State<_PendingActivateDateDialog> createState() =>
      _PendingActivateDateDialogState();
}

class _PendingActivateDateDialogState extends State<_PendingActivateDateDialog> {
  late DateTime _selected;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final seed = widget.initial ?? DateTime(now.year, now.month, now.day);
    _selected = DateTime(seed.year, seed.month, seed.day);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state.strings;
    return AppAdaptiveDialogShell(
      title: Text(s['taskPendingTitle']),
      width: AppDialogMetrics.maxWidth,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s['cancel']),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _selected),
          child: Text(s['ok']),
        ),
      ],
      child: AppCompactCalendar(
        title: s['taskPendingDate'],
        weekdayLabels: s.narrowWeekdaysSundayFirst,
        formatMonth: s.monthYear,
        isMarked: (date) =>
            date.year == _selected.year &&
            date.month == _selected.month &&
            date.day == _selected.day,
        caption: s['taskPendingHint'],
        onDaySelected: (date) {
          setState(() => _selected = date);
        },
      ),
    );
  }
}
