/// The schedule string the backend's `next_run_after()` reads.
///
/// Daily / weekly / monthly, never a cron line. The create form used to send
/// `0 8 * * *` at a parser that only knows `daily 08:00`, which is why a
/// scheduled automation could never have fired on time.
class AutomationSchedule {
  const AutomationSchedule({
    required this.kind,
    this.time = '08:00',
    this.weekday = 'mon',
    this.placement = 'first',
  });

  /// Twin of `DEFAULT_AUTOMATION_TIMEZONE` in
  /// `areas/automations/services/automation_schedule.py`.
  static const defaultTimezone = 'Asia/Jerusalem';

  static const kinds = ['daily', 'weekly', 'monthly'];
  static const weekdays = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
  static const placements = ['first', 'second', 'third', 'last'];

  static const weekdayKeys = {
    'mon': 'monday',
    'tue': 'tuesday',
    'wed': 'wednesday',
    'thu': 'thursday',
    'fri': 'friday',
    'sat': 'saturday',
    'sun': 'sunday',
  };

  final String kind;
  final String time;
  final String weekday;
  final String placement;

  String toDsl() {
    final clock = _normaliseTime(time);
    return switch (kind) {
      'weekly' => 'weekly $weekday $clock',
      'monthly' => 'monthly $placement $weekday $clock',
      _ => 'daily $clock',
    };
  }

  AutomationSchedule copyWith({
    String? kind,
    String? time,
    String? weekday,
    String? placement,
  }) {
    return AutomationSchedule(
      kind: kind ?? this.kind,
      time: time ?? this.time,
      weekday: weekday ?? this.weekday,
      placement: placement ?? this.placement,
    );
  }

  /// Unreadable strings become a daily 08:00 rather than a crash — the form
  /// has to open even for a row someone typed by hand.
  static AutomationSchedule parse(String? raw) {
    final parts = (raw ?? '').trim().toLowerCase().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) {
      return const AutomationSchedule(kind: 'daily');
    }
    final kind = parts.first;
    if (kind == 'weekly') {
      return AutomationSchedule(
        kind: 'weekly',
        weekday: _weekday(parts.length > 1 ? parts[1] : 'mon'),
        time: _normaliseTime(parts.length > 2 ? parts[2] : '08:00'),
      );
    }
    if (kind == 'monthly') {
      return AutomationSchedule(
        kind: 'monthly',
        placement: placements.contains(parts.length > 1 ? parts[1] : '')
            ? parts[1]
            : 'first',
        weekday: _weekday(parts.length > 2 ? parts[2] : 'mon'),
        time: _normaliseTime(parts.length > 3 ? parts[3] : '08:00'),
      );
    }
    if (kind == 'daily') {
      return AutomationSchedule(
        kind: 'daily',
        time: _normaliseTime(parts.length > 1 ? parts[1] : '08:00'),
      );
    }
    return const AutomationSchedule(kind: 'daily');
  }

  static String weekdayFromDart(int dartWeekday) {
    final index = (dartWeekday - 1).clamp(0, 6);
    return weekdays[index];
  }

  int get dartWeekday {
    final index = weekdays.indexOf(weekday);
    return (index < 0 ? 0 : index) + 1;
  }

  /// First / second / third / last occurrence of this date's weekday in its month.
  static String placementFromDate(DateTime date) {
    final days = _weekdayDaysInMonth(date.year, date.month, date.weekday);
    final index = days.indexOf(date.day);
    if (index < 0) return 'first';
    if (index == days.length - 1) return 'last';
    return placements[index.clamp(0, placements.length - 2)];
  }

  /// Weekly takes the weekday; monthly also infers first / second / third / last.
  AutomationSchedule applyingDate(DateTime date) {
    final day = weekdayFromDart(date.weekday);
    if (kind == 'monthly') {
      return copyWith(weekday: day, placement: placementFromDate(date));
    }
    if (kind == 'weekly') {
      return copyWith(weekday: day);
    }
    return this;
  }

  /// Which days in [month] this schedule would fire (weekly: every matching
  /// weekday; monthly: the inferred placement).
  bool marksDate(DateTime date) {
    if (kind == 'weekly') return date.weekday == dartWeekday;
    if (kind == 'monthly') {
      final day = occurrenceDay(date.year, date.month);
      return day != null && date.day == day;
    }
    return false;
  }

  int? occurrenceDay(int year, int month) {
    final days = _weekdayDaysInMonth(year, month, dartWeekday);
    if (days.isEmpty) return null;
    if (placement == 'last') return days.last;
    final index = placements.indexOf(placement);
    if (index < 0 || index >= days.length) return null;
    return days[index];
  }

  static List<int> _weekdayDaysInMonth(int year, int month, int dartWeekday) {
    final last = DateTime(year, month + 1, 0).day;
    return [
      for (var day = 1; day <= last; day++)
        if (DateTime(year, month, day).weekday == dartWeekday) day,
    ];
  }

  static String _weekday(String raw) {
    if (weekdays.contains(raw)) return raw;
    for (final entry in weekdayKeys.entries) {
      if (entry.value == raw) return entry.key;
    }
    return 'mon';
  }

  static String _normaliseTime(String raw) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(raw.trim());
    if (match == null) return '08:00';
    final hour = int.parse(match.group(1)!).clamp(0, 23);
    final minute = int.parse(match.group(2)!).clamp(0, 59);
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }
}
