final _bulletPrefix = RegExp(r'^\s*(?:[•\-\*]|\d+[\.\)])\s*');
final _listClipboardLine = RegExp(r'^\s*(?:[•\-\*]|\d+[\.\)])\s+');
final _orderedClipboardLine = RegExp(r'^\s*\d+[\.\)]\s+');

/// Notes / Word / old Mac often use `\r` or Unicode separators, not `\n`.
String normalizePasteLineBreaks(String raw) {
  return raw
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll('\u2028', '\n')
      .replaceAll('\u2029', '\n');
}

List<String> _nonEmptyClipboardLines(String raw) {
  return [
    for (final line in normalizePasteLineBreaks(raw).split('\n'))
      if (line.trim().isNotEmpty) line,
  ];
}

/// True when every non-empty line already looks like a bullet or numbered item.
bool clipboardLooksLikeList(String raw) {
  final lines = _nonEmptyClipboardLines(raw);
  if (lines.isEmpty) return false;
  return lines.every(_listClipboardLine.hasMatch);
}

bool clipboardLooksLikeOrderedList(String raw) {
  final lines = _nonEmptyClipboardLines(raw);
  if (lines.isEmpty) return false;
  return lines.every(_orderedClipboardLine.hasMatch);
}

/// One list item per newline. Strips an existing `-` / `1.` prefix if present.
List<String> listItemTextsFromMarkedText(String raw) {
  return [
    for (final line in normalizePasteLineBreaks(raw).split('\n'))
      line.replaceFirst(_bulletPrefix, '').trim(),
  ].where((s) => s.isNotEmpty).toList();
}

/// Marker-body lines (`- …` / `1. …`) for the Super Editor list parser.
String clipboardListAsMarkerBody(String raw, {required bool ordered}) {
  final texts = [
    for (final line in _nonEmptyClipboardLines(raw))
      line.replaceFirst(_bulletPrefix, '').trim(),
  ].where((s) => s.isNotEmpty).toList();
  final buffer = StringBuffer();
  for (var i = 0; i < texts.length; i++) {
    if (i > 0) buffer.writeln();
    buffer.write(ordered ? '${i + 1}. ${texts[i]}' : '- ${texts[i]}');
  }
  return buffer.toString();
}

/// First line stays in the focused task; the rest become new tasks after it.
/// `null` when the paste is a single line (or empty).
({String first, List<String> following})? splitPastedTaskLines(String raw) {
  final lines = parsePastedListText(raw);
  if (lines.length < 2) return null;
  return (first: lines.first, following: lines.sublist(1));
}

/// Splits pasted plain text into list/task lines (bullets, numbers, newlines, `;`).
List<String> parsePastedListText(String raw) {
  final normalized = normalizePasteLineBreaks(raw).trim();
  if (normalized.isEmpty) return [];

  final List<String> lines;
  if (!normalized.contains('\n') && normalized.contains(';')) {
    lines = normalized
        .split(';')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  } else {
    lines = normalized
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  return [
    for (final line in lines)
      line.replaceFirst(_bulletPrefix, '').trim(),
  ].where((s) => s.isNotEmpty).toList();
}

String serializeListLines(Iterable<String> lines) => lines.join('\n');

/// Document helpers for [ConnectedLinesEditor] — one logical item per newline.
List<String> normalizeDocumentLines(List<String> lines) {
  if (lines.isEmpty) return [''];
  return [...lines];
}

String documentFromLines(List<String> lines) {
  if (lines.isEmpty) return '';
  return lines.join('\n');
}

List<String> linesFromDocument(String text) {
  if (text.isEmpty) return [''];
  return text.split('\n');
}
