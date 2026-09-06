/// Checkbox lines stored in an info body — not [Task] rows.
///
/// A line matching `☐` / `☑` (or legacy `- [ ]` / `- [x]` / `- ☐`) is an
/// inner task. Preferred storage is the glyph alone — no list dash.
library;

final _line = RegExp(
  r'^(\s*)(?:([-*])\s+)?(?:\[([ xX])\]|([☐☑]))\s?(.*)$',
);

class InnerTaskLine {
  const InnerTaskLine({
    required this.start,
    required this.end,
    required this.markStart,
    required this.markEnd,
    required this.done,
    required this.title,
    required this.indent,
  });

  final int start;
  final int end;
  final int markStart;
  final int markEnd;
  final bool done;
  final String title;
  final String indent;
}

class InnerTaskEdit {
  const InnerTaskEdit({required this.text, required this.caret});

  final String text;
  final int caret;
}

List<InnerTaskLine> parseInnerTaskLines(String body) {
  final items = <InnerTaskLine>[];
  var offset = 0;
  final lines = body.split('\n');
  for (final raw in lines) {
    final match = _line.firstMatch(raw);
    final lineEnd = offset + raw.length;
    if (match != null) {
      final indent = match.group(1) ?? '';
      final bullet = match.group(2);
      final box = match.group(3);
      final glyph = match.group(4);
      final title = match.group(5) ?? '';
      final prefixLen = indent.length + (bullet != null ? 2 : 0);
      late final bool done;
      late final int markStart;
      late final int markEnd;
      if (box != null) {
        done = box.toLowerCase() == 'x';
        markStart = offset + prefixLen;
        markEnd = markStart + 3;
      } else {
        done = glyph == '☑';
        markStart = offset + prefixLen;
        markEnd = markStart + 1;
      }
      items.add(
        InnerTaskLine(
          start: offset,
          end: lineEnd,
          markStart: markStart,
          markEnd: markEnd,
          done: done,
          title: title,
          indent: indent,
        ),
      );
    }
    offset = lineEnd + 1;
  }
  return items;
}

/// `true` all done, `false` all active, `null` none or mixed.
bool? innerTasksUnanimous(String body) {
  final items = parseInnerTaskLines(body);
  if (items.isEmpty) return null;
  if (items.every((item) => item.done)) return true;
  if (items.every((item) => !item.done)) return false;
  return null;
}

String _renderLine(InnerTaskLine item, {required bool done}) {
  final mark = done ? '☑' : '☐';
  final title = item.title;
  return '${item.indent}$mark${title.isEmpty ? '' : ' $title'}';
}

String setAllInnerTasks(String body, {required bool done}) {
  final items = parseInnerTaskLines(body);
  if (items.isEmpty) return body;
  final byStart = {for (final item in items) item.start: item};
  var offset = 0;
  final out = <String>[];
  for (final raw in body.split('\n')) {
    final item = byStart[offset];
    out.add(item == null ? raw : _renderLine(item, done: done));
    offset += raw.length + 1;
  }
  return out.join('\n');
}

/// Rewrite bracket / dashed forms to preferred `☐` / `☑` lines.
String canonicalizeInnerTaskMarks(String body) {
  final items = parseInnerTaskLines(body);
  if (items.isEmpty) return body;
  final byStart = {for (final item in items) item.start: item};
  var offset = 0;
  final out = <String>[];
  var changed = false;
  for (final raw in body.split('\n')) {
    final item = byStart[offset];
    if (item == null) {
      out.add(raw);
    } else {
      final next = _renderLine(item, done: item.done);
      out.add(next);
      if (next != raw) changed = true;
    }
    offset += raw.length + 1;
  }
  return changed ? out.join('\n') : body;
}

InnerTaskLine? innerTaskAt(String body, int offset) {
  for (final item in parseInnerTaskLines(body)) {
    if (offset >= item.start && offset <= item.end) return item;
  }
  return null;
}

bool tapHitsInnerTaskMark(String body, int offset) {
  for (final item in parseInnerTaskLines(body)) {
    if (offset >= item.markStart && offset < item.markEnd) return true;
  }
  return false;
}

String? toggleInnerTaskAt(String body, int offset) {
  final items = parseInnerTaskLines(body);
  InnerTaskLine? hit;
  for (final item in items) {
    if (offset >= item.markStart && offset < item.markEnd) {
      hit = item;
      break;
    }
  }
  if (hit == null) return null;
  final byStart = {for (final item in items) item.start: item};
  var cursor = 0;
  final out = <String>[];
  final flipped = hit;
  for (final raw in body.split('\n')) {
    final item = byStart[cursor];
    out.add(
      item == flipped ? _renderLine(flipped, done: !flipped.done) : raw,
    );
    cursor += raw.length + 1;
  }
  return out.join('\n');
}

/// Combined title\\nbody helpers — inner tasks live in the body only.

(String title, String body) _split(String combined) {
  final nl = combined.indexOf('\n');
  if (nl < 0) return (combined, '');
  return (combined.substring(0, nl), combined.substring(nl + 1));
}

String _join(String title, String body) {
  if (body.isEmpty) return title;
  return '$title\n$body';
}

int _bodyOffset(String combined) {
  final nl = combined.indexOf('\n');
  return nl < 0 ? -1 : nl + 1;
}

bool tapHitsCombinedInnerMark(String combined, int offset) {
  final bodyAt = _bodyOffset(combined);
  if (bodyAt < 0 || offset < bodyAt) return false;
  return tapHitsInnerTaskMark(combined.substring(bodyAt), offset - bodyAt);
}

String? toggleCombinedInnerTask(String combined, int offset) {
  final bodyAt = _bodyOffset(combined);
  if (bodyAt < 0 || offset < bodyAt) return null;
  final next = toggleInnerTaskAt(combined.substring(bodyAt), offset - bodyAt);
  if (next == null) return null;
  return _join(combined.substring(0, bodyAt - 1), next);
}

String setAllCombinedInnerTasks(String combined, {required bool done}) {
  final parts = _split(combined);
  return _join(parts.$1, setAllInnerTasks(parts.$2, done: done));
}

bool? combinedInnerTasksUnanimous(String combined) {
  return innerTasksUnanimous(_split(combined).$2);
}

const _fresh = '☐ ';

String _lineToInnerTask(String raw) {
  final match = _line.firstMatch(raw);
  if (match != null) {
    final indent = match.group(1) ?? '';
    final box = match.group(3);
    final glyph = match.group(4);
    final title = match.group(5) ?? '';
    final done = box != null ? box.toLowerCase() == 'x' : glyph == '☑';
    return _renderLine(
      InnerTaskLine(
        start: 0,
        end: raw.length,
        markStart: 0,
        markEnd: 1,
        done: done,
        title: title,
        indent: indent,
      ),
      done: done,
    );
  }
  final indent = RegExp(r'^(\s*)').firstMatch(raw)?.group(1) ?? '';
  var content = raw.substring(indent.length);
  if (content.trim().isEmpty) return raw;
  final bare = RegExp(r'^[-*]\s+(.*)$').firstMatch(content);
  if (bare != null) content = bare.group(1) ?? '';
  return '$indent☐${content.isEmpty ? '' : ' $content'}';
}

/// Insert a fresh empty checkbox line (menu / ⌘T while in an info).
InnerTaskEdit insertInnerTaskAtCaret(String combined, int caret) {
  final parts = _split(combined);
  final title = parts.$1;
  final body = parts.$2;
  final bodyAt = _bodyOffset(combined);

  if (bodyAt < 0 || caret < bodyAt) {
    if (body.isEmpty) {
      return InnerTaskEdit(
        text: '$title\n$_fresh',
        caret: title.length + 1 + _fresh.length,
      );
    }
    final nextBody = '$_fresh\n$body';
    return InnerTaskEdit(
      text: _join(title, nextBody),
      caret: title.length + 1 + _fresh.length,
    );
  }

  final local = (caret - bodyAt).clamp(0, body.length);
  final item = innerTaskAt(body, local);
  if (item != null) {
    if (item.title.trim().isEmpty) {
      final caretAt = bodyAt + item.start + '${item.indent}$_fresh'.length;
      return InnerTaskEdit(text: combined, caret: caretAt);
    }
    return insertInnerTaskLineOnEnter(combined, caret)!;
  }

  final lineStart = body.lastIndexOf('\n', local <= 0 ? 0 : local - 1) + 1;
  final lineEnd = body.indexOf('\n', lineStart);
  final end = lineEnd < 0 ? body.length : lineEnd;
  final line = body.substring(lineStart, end);
  if (line.trim().isEmpty) {
    final indent = RegExp(r'^(\s*)').firstMatch(line)?.group(1) ?? '';
    final nextLine = '$indent$_fresh';
    final nextBody = body.replaceRange(lineStart, end, nextLine);
    return InnerTaskEdit(
      text: _join(title, nextBody),
      caret: bodyAt + lineStart + nextLine.length,
    );
  }
  final prefix = '\n$_fresh';
  final nextBody = body.replaceRange(end, end, prefix);
  return InnerTaskEdit(
    text: _join(title, nextBody),
    caret: bodyAt + end + prefix.length,
  );
}

/// Marked body lines become inner tasks (menu / ⌘T with a non-empty mark).
InnerTaskEdit convertSelectionToInnerTasks(
  String combined,
  int selectionStart,
  int selectionEnd,
) {
  var a = selectionStart;
  var b = selectionEnd;
  if (a > b) {
    final t = a;
    a = b;
    b = t;
  }
  if (a == b) return insertInnerTaskAtCaret(combined, a);

  final parts = _split(combined);
  final title = parts.$1;
  final body = parts.$2;
  final bodyAt = _bodyOffset(combined);

  // Selection must touch the body — title-only marks just insert.
  if (bodyAt < 0 || b <= bodyAt) {
    return insertInnerTaskAtCaret(combined, b);
  }

  final bodyStart = a <= bodyAt ? 0 : a - bodyAt;
  final bodyEnd = (b - bodyAt).clamp(0, body.length);
  if (bodyEnd <= bodyStart) {
    return insertInnerTaskAtCaret(combined, b);
  }

  final lineStart =
      body.lastIndexOf('\n', bodyStart <= 0 ? 0 : bodyStart - 1) + 1;
  // Include the whole last touched line (even if the mark ends mid-line).
  final lastBreak = body.indexOf('\n', bodyEnd > 0 ? bodyEnd - 1 : 0);
  final rangeEnd = lastBreak < 0 ? body.length : lastBreak;

  final range = body.substring(lineStart, rangeEnd);
  if (range.split('\n').every((line) => line.trim().isEmpty)) {
    return insertInnerTaskAtCaret(combined, b);
  }
  final converted = range.split('\n').map(_lineToInnerTask).join('\n');
  final nextBody = body.replaceRange(lineStart, rangeEnd, converted);
  return InnerTaskEdit(
    text: _join(title, nextBody),
    caret: bodyAt + lineStart + converted.length,
  );
}

/// `- ` / `* ` at the start of a body line becomes `☐ `.
InnerTaskEdit? promoteBareDashToCheckbox(String combined, int caret) {
  final bodyAt = _bodyOffset(combined);
  if (bodyAt < 0 || caret < bodyAt) return null;
  final body = combined.substring(bodyAt);
  final local = caret - bodyAt;
  final lineStart = body.lastIndexOf('\n', local - 1) + 1;
  final lineEnd = body.indexOf('\n', lineStart);
  final end = lineEnd < 0 ? body.length : lineEnd;
  final line = body.substring(lineStart, end);
  final match = RegExp(r'^(\s*)([-*])\s$').firstMatch(line);
  if (match == null) return null;
  if (local != lineStart + line.length) return null;
  final indent = match.group(1) ?? '';
  final nextLine = '$indent$_fresh';
  final nextBody = body.replaceRange(lineStart, end, nextLine);
  return InnerTaskEdit(
    text: _join(combined.substring(0, bodyAt - 1), nextBody),
    caret: bodyAt + lineStart + nextLine.length,
  );
}

/// Plain Enter on a checkbox line: next item, or drop an empty prefix.
InnerTaskEdit? insertInnerTaskLineOnEnter(String combined, int caret) {
  final bodyAt = _bodyOffset(combined);
  if (bodyAt < 0 || caret < bodyAt) return null;
  final body = combined.substring(bodyAt);
  final local = (caret - bodyAt).clamp(0, body.length);
  final item = innerTaskAt(body, local);
  if (item == null) return null;
  if (item.title.trim().isEmpty) {
    final title = combined.substring(0, bodyAt - 1);
    final nextBody = body.replaceRange(item.start, item.end, item.indent);
    if (nextBody.isEmpty) {
      return InnerTaskEdit(text: '$title\n', caret: title.length + 1);
    }
    return InnerTaskEdit(
      text: _join(title, nextBody),
      caret: bodyAt + item.start + item.indent.length,
    );
  }
  final insertAt = item.end;
  final prefix = '\n$_fresh';
  final nextBody = body.replaceRange(insertAt, insertAt, prefix);
  return InnerTaskEdit(
    text: _join(combined.substring(0, bodyAt - 1), nextBody),
    caret: bodyAt + insertAt + prefix.length,
  );
}

/// Backspace on an empty checkbox (or at the mark) removes the prefix.
InnerTaskEdit? backspaceInnerTaskPrefix(String combined, int caret) {
  final bodyAt = _bodyOffset(combined);
  if (bodyAt < 0 || caret < bodyAt) return null;
  final body = combined.substring(bodyAt);
  final local = caret - bodyAt;
  final item = innerTaskAt(body, local);
  if (item == null) return null;
  final atMark = local <= item.markEnd && local >= item.start;
  if (!atMark && !(item.title.isEmpty && local == item.end)) return null;
  if (item.title.isNotEmpty && local > item.markEnd) return null;
  final title = combined.substring(0, bodyAt - 1);
  final nextBody = body.replaceRange(item.start, item.end, item.indent);
  if (nextBody.isEmpty) {
    return InnerTaskEdit(text: '$title\n', caret: title.length + 1);
  }
  return InnerTaskEdit(
    text: _join(title, nextBody),
    caret: bodyAt + item.start + item.indent.length,
  );
}
