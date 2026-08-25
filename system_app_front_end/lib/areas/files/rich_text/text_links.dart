/// First http(s) or www URL in [text], with offsets in that string.
({int start, int end, String url})? firstUrlIn(String text) {
  final match = _urlRe.firstMatch(text);
  if (match == null) return null;
  final raw = match.group(0)!;
  return (start: match.start, end: match.end, url: launchableUrl(raw));
}

String launchableUrl(String raw) {
  final trimmed = raw.trim();
  if (trimmed.toLowerCase().startsWith('www.')) return 'https://$trimmed';
  return trimmed;
}

Uri? launchableUri(String raw) {
  final url = launchableUrl(raw);
  return Uri.tryParse(url);
}

final _urlRe = RegExp(
  r'(https?://[^\s<>\]]+|www\.[^\s<>\]]+)',
  caseSensitive: false,
);
