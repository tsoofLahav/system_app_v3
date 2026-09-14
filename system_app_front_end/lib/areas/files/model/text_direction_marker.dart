/// Optional paragraph/list-item direction metadata in v4 marker text.
/// This prefix is storage syntax, never part of the editable plain string.
abstract final class TextDirectionMarker {
  static final _prefix = RegExp(r'^\[DIR (rtl|ltr)\]');
  static String? direction(String text) => _prefix.firstMatch(text)?.group(1);
  static String strip(String text) {
    final match = _prefix.firstMatch(text);
    return match == null ? text : text.substring(match.end);
  }

  static String encode(String text, Object? direction) =>
      direction == 'rtl' || direction == 'ltr' ? '[DIR $direction]$text' : text;
}
