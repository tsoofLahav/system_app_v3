final _bulletPrefix = RegExp(r'^\s*(?:[•\-\*]|\d+[\.\)])\s*');

/// Splits pasted plain text into list/task lines (bullets, numbers, newlines, `;`).
List<String> parsePastedListText(String raw) {
  final normalized = raw.replaceAll('\r\n', '\n').trim();
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
