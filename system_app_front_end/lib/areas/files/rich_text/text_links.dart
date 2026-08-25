import 'dart:async';

import 'package:url_launcher/url_launcher.dart';

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

/// `link` on a payload span covering [offset], if any.
String? urlAtSpanOffset(List<Map<String, dynamic>> spans, int offset) {
  for (final span in spans) {
    final start = span['start'];
    final end = span['end'];
    if (start is! int || end is! int) continue;
    if (offset < start || offset >= end) continue;
    final link = span['link'];
    if (link is String && link.trim().isNotEmpty) return link;
  }
  return null;
}

Future<void> openWebLink(String raw) async {
  final uri = launchableUri(raw);
  if (uri == null) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

final _urlRe = RegExp(
  r'(https?://[^\s<>\]]+|www\.[^\s<>\]]+)',
  caseSensitive: false,
);
