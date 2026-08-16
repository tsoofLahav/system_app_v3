/// Clock hints for an agent run.
///
/// The model has no clock of its own — without these it writes a date from
/// memory. The backend falls back to server UTC, so send the user's local day.
Map<String, String> agentTimeHints([DateTime? now]) {
  final local = (now ?? DateTime.now()).toLocal();
  return {
    'today': _isoDate(local),
    'weekday': _weekdayNames[local.weekday - 1],
    'now': '${_isoDate(local)}T${_clock(local)}${_utcOffset(local)}',
  };
}

// English keys travel to the API; the UI never shows these.
const List<String> _weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${_two(d.month)}-${_two(d.day)}';

String _clock(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}';

String _utcOffset(DateTime d) {
  final offset = d.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final minutes = offset.inMinutes.abs();
  return '$sign${_two(minutes ~/ 60)}:${_two(minutes % 60)}';
}

String _two(int value) => value.toString().padLeft(2, '0');
