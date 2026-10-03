/// Ordinary bullet lines in an info body. Stored as text, never task rows.
library;

import 'inner_tasks.dart';

final _bullet = RegExp(r'^([ \t]*)•(?: (.*))?$');

/// Add a bullet below the caret, or convert the selected body lines.
InnerTaskEdit insertInnerList(String text, int start, int end) {
  final newline = text.indexOf('\n');
  if (newline < 0) {
    return InnerTaskEdit(text: '$text\n• ', caret: text.length + 3);
  }
  final bodyAt = newline + 1;
  if (end < bodyAt) {
    return InnerTaskEdit(
      text: text.replaceRange(bodyAt, bodyAt, '• \n'),
      caret: bodyAt + 2,
    );
  }
  start = start.clamp(bodyAt, text.length);
  end = end.clamp(start, text.length);
  final lineStart = text.lastIndexOf('\n', start - 1) + 1;
  final lastBreak = text.indexOf('\n', end > start ? end - 1 : end);
  final lineEnd = lastBreak < 0 ? text.length : lastBreak;
  if (start != end) {
    final converted = text
        .substring(lineStart, lineEnd)
        .split('\n')
        .map((line) {
          if (line.trim().isEmpty || _bullet.hasMatch(line)) return line;
          final task = parseInnerTaskLines(line).firstOrNull;
          if (task != null) return '${task.indent}• ${task.title}';
          final indent = RegExp(r'^[ \t]*').stringMatch(line)!;
          final content = line
              .substring(indent.length)
              .replaceFirst(RegExp(r'^[-*] '), '');
          return '$indent• $content';
        })
        .join('\n');
    return InnerTaskEdit(
      text: text.replaceRange(lineStart, lineEnd, converted),
      caret: lineStart + converted.length,
    );
  }
  final continued = continueInnerList(text, start);
  if (continued != null) return continued;
  final line = text.substring(lineStart, lineEnd);
  if (line.trim().isEmpty) {
    return InnerTaskEdit(
      text: text.replaceRange(lineStart, lineEnd, '$line• '),
      caret: lineEnd + 2,
    );
  }
  return InnerTaskEdit(
    text: text.replaceRange(lineEnd, lineEnd, '\n• '),
    caret: lineEnd + 3,
  );
}

/// Enter splits a filled bullet at the caret; an empty bullet becomes prose.
InnerTaskEdit? continueInnerList(String text, int caret) {
  final bodyAt = text.indexOf('\n') + 1;
  if (bodyAt == 0 || caret < bodyAt) return null;
  final start = text.lastIndexOf('\n', caret - 1) + 1;
  final nextBreak = text.indexOf('\n', caret);
  final end = nextBreak < 0 ? text.length : nextBreak;
  final match = _bullet.firstMatch(text.substring(start, end));
  if (match == null) return null;
  final indent = match.group(1)!;
  if ((match.group(2) ?? '').trim().isEmpty) {
    return InnerTaskEdit(
      text: text.replaceRange(start, end, indent),
      caret: start + indent.length,
    );
  }
  final at = caret.clamp(start + indent.length + 2, end);
  final prefix = '\n$indent• ';
  return InnerTaskEdit(
    text: text.replaceRange(at, at, prefix),
    caret: at + prefix.length,
  );
}

/// Backspace at a bullet's content start removes only its prefix.
InnerTaskEdit? backspaceInnerList(String text, int caret) {
  final bodyAt = text.indexOf('\n') + 1;
  if (bodyAt == 0 || caret < bodyAt) return null;
  final start = text.lastIndexOf('\n', caret - 1) + 1;
  final nextBreak = text.indexOf('\n', caret);
  final end = nextBreak < 0 ? text.length : nextBreak;
  final match = _bullet.firstMatch(text.substring(start, end));
  if (match == null) return null;
  final prefixStart = start + match.group(1)!.length;
  final prefixEnd = (prefixStart + 2).clamp(prefixStart, end);
  if (caret < prefixStart || caret > prefixEnd) return null;
  return InnerTaskEdit(
    text: text.replaceRange(prefixStart, prefixEnd, ''),
    caret: prefixStart,
  );
}

/// A dash followed by a space starts an ordinary list in the info body.
InnerTaskEdit? promoteBareDashToInnerList(String text, int caret) {
  final bodyAt = text.indexOf('\n') + 1;
  if (bodyAt == 0 || caret <= bodyAt || caret > text.length) return null;
  final start = text.lastIndexOf('\n', caret - 1) + 1;
  final nextBreak = text.indexOf('\n', start);
  final end = nextBreak < 0 ? text.length : nextBreak;
  if (caret != end) return null;
  final match = RegExp(r'^([ \t]*)- $').firstMatch(text.substring(start, end));
  if (match == null) return null;
  final line = '${match.group(1)}• ';
  return InnerTaskEdit(
    text: text.replaceRange(start, end, line),
    caret: start + line.length,
  );
}
