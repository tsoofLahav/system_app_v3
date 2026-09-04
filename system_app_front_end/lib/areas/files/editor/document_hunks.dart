import '../../production_agent/pending_review_service.dart';

/// Opcode: (tag, i1, i2, j1, j2) — same shape as Python difflib.
typedef TextOpcode = (String, int, int, int, int);

class _Match {
  const _Match(this.a, this.b, this.size);
  final int a;
  final int b;
  final int size;
}

List<_Match> _matchingBlocks(List<String> a, List<String> b) {
  final n = a.length;
  final m = b.length;
  final dp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      if (a[i] == b[j]) {
        dp[i][j] = dp[i + 1][j + 1] + 1;
      } else {
        dp[i][j] = dp[i + 1][j] >= dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1];
      }
    }
  }
  final matches = <_Match>[];
  var i = 0;
  var j = 0;
  while (i < n && j < m) {
    if (a[i] == b[j]) {
      final startI = i;
      final startJ = j;
      while (i < n && j < m && a[i] == b[j]) {
        i++;
        j++;
      }
      matches.add(_Match(startI, startJ, i - startI));
    } else if (dp[i + 1][j] >= dp[i][j + 1]) {
      i++;
    } else {
      j++;
    }
  }
  matches.add(_Match(n, m, 0));
  return matches;
}

List<TextOpcode> sequenceOpcodes(List<String> a, List<String> b) {
  final out = <TextOpcode>[];
  var i1 = 0;
  var j1 = 0;
  for (final match in _matchingBlocks(a, b)) {
    if (i1 < match.a || j1 < match.b) {
      if (i1 < match.a && j1 < match.b) {
        out.add(('replace', i1, match.a, j1, match.b));
      } else if (i1 < match.a) {
        out.add(('delete', i1, match.a, j1, match.b));
      } else {
        out.add(('insert', i1, match.a, j1, match.b));
      }
    }
    if (match.size > 0) {
      out.add((
        'equal',
        match.a,
        match.a + match.size,
        match.b,
        match.b + match.size,
      ));
    }
    i1 = match.a + match.size;
    j1 = match.b + match.size;
  }
  return out;
}

List<TextOpcode> coalesceOpcodes(List<TextOpcode> opcodes) {
  if (opcodes.isEmpty) return const [];
  final out = <TextOpcode>[];
  var i = 0;
  while (i < opcodes.length) {
    final (tag, i1, i2, j1, j2) = opcodes[i];
    if (i + 1 < opcodes.length) {
      final (ntag, ni1, ni2, nj1, nj2) = opcodes[i + 1];
      if (tag == 'delete' && ntag == 'insert' && i2 == ni1 && j2 == nj1) {
        out.add(('replace', i1, i2, j1, nj2));
        i += 2;
        continue;
      }
      if (tag == 'insert' && ntag == 'delete' && i2 == ni1 && j2 == nj1) {
        out.add(('replace', i1, ni2, j1, j2));
        i += 2;
        continue;
      }
    }
    out.add((tag, i1, i2, j1, j2));
    i++;
  }
  return out;
}

List<TextOpcode> splitOpcodesToLines(List<TextOpcode> opcodes) {
  final out = <TextOpcode>[];
  for (final (tag, i1, i2, j1, j2) in opcodes) {
    if (tag == 'equal') {
      out.add((tag, i1, i2, j1, j2));
      continue;
    }
    if (tag == 'insert') {
      for (var j = j1; j < j2; j++) {
        out.add(('insert', i1, i2, j, j + 1));
      }
      continue;
    }
    if (tag == 'delete') {
      for (var i = i1; i < i2; i++) {
        out.add(('delete', i, i + 1, j1, j2));
      }
      continue;
    }
    final oldN = i2 - i1;
    final newN = j2 - j1;
    final paired = oldN < newN ? oldN : newN;
    for (var k = 0; k < paired; k++) {
      out.add(('replace', i1 + k, i1 + k + 1, j1 + k, j1 + k + 1));
    }
    var cursorJ = j1 + paired;
    for (var i = i1 + paired; i < i2; i++) {
      out.add(('delete', i, i + 1, cursorJ, cursorJ));
    }
    final cursorI = i1 + paired;
    for (var j = j1 + paired; j < j2; j++) {
      out.add(('insert', cursorI, cursorI, j, j + 1));
    }
  }
  return out;
}

List<TextOpcode> normalizedOpcodes(String oldText, String newText) {
  final raw = sequenceOpcodes(_linesOf(oldText), _linesOf(newText));
  return splitOpcodesToLines(coalesceOpcodes(raw));
}

List<String> _linesOf(String text) {
  if (text.isEmpty) return [];
  final lines = text.split('\n');
  if (lines.isNotEmpty && lines.last.isEmpty && text.endsWith('\n')) {
    lines.removeLast();
  }
  return lines;
}

List<PendingReviewHunk> buildHunks(String oldText, String newText) {
  final oldLines = _linesOf(oldText);
  final newLines = _linesOf(newText);
  final hunks = <PendingReviewHunk>[];
  for (final (tag, i1, i2, j1, j2) in normalizedOpcodes(oldText, newText)) {
    if (tag == 'equal') continue;
    final op = switch (tag) {
      'insert' => 'add',
      'delete' => 'remove',
      'replace' => 'change',
      _ => tag,
    };
    hunks.add(
      PendingReviewHunk(
        id: '$op-$i1-$j1',
        op: op,
        oldStart: i1 + 1,
        oldEnd: i2,
        newStart: j1 + 1,
        newEnd: j2,
        oldLines: oldLines.sublist(i1, i2),
        newLines: newLines.sublist(j1, j2),
      ),
    );
  }
  return hunks;
}

/// Returns merged text, or null when a decision is missing / invalid.
String? mergeHunkTexts(
  String oldText,
  String newText,
  List<Map<String, String>> decisions,
) {
  final oldLines = _linesOf(oldText);
  final newLines = _linesOf(newText);
  final opcodes = normalizedOpcodes(oldText, newText);
  final hunks = buildHunks(oldText, newText);
  final byId = {for (final d in decisions) d['hunk_id'] ?? '': d['choice']};
  if (hunks.length != byId.length || hunks.any((h) => !byId.containsKey(h.id))) {
    return null;
  }
  for (final h in hunks) {
    final choice = byId[h.id];
    if (choice != 'accept' && choice != 'reject') return null;
  }

  final out = <String>[];
  final hunkIter = hunks.iterator;
  for (final (tag, i1, i2, j1, j2) in opcodes) {
    if (tag == 'equal') {
      out.addAll(oldLines.sublist(i1, i2));
      continue;
    }
    if (!hunkIter.moveNext()) return null;
    final accept = byId[hunkIter.current.id] == 'accept';
    if (tag == 'insert') {
      if (accept) out.addAll(newLines.sublist(j1, j2));
    } else if (tag == 'delete') {
      if (!accept) out.addAll(oldLines.sublist(i1, i2));
    } else if (tag == 'replace') {
      out.addAll(accept ? newLines.sublist(j1, j2) : oldLines.sublist(i1, i2));
    }
  }
  var text = out.join('\n');
  if (oldText.endsWith('\n') || newText.endsWith('\n')) {
    if (text.isNotEmpty && !text.endsWith('\n')) text = '$text\n';
  }
  return text;
}
