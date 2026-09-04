import '../model/document_text_codec.dart';
import './document_hunks.dart';

class ThreeWayResult {
  const ThreeWayResult({
    required this.hasConflicts,
    required this.merged,
    required this.localSided,
    required this.serverSided,
  });

  final bool hasConflicts;

  /// Auto-merged marker text when [hasConflicts] is false.
  final String merged;

  /// Auto-merged spine with local text on leftover overlaps.
  final String localSided;

  /// Auto-merged spine with server text on leftover overlaps.
  final String serverSided;
}

class _Range {
  const _Range(this.lo, this.hi);
  final int lo;
  final int hi;
}

bool _rangesOverlap(_Range a, _Range b) {
  if (a.lo == a.hi && b.lo == b.hi) return a.lo == b.lo;
  if (a.lo == a.hi) return b.lo <= a.lo && a.lo < b.hi;
  if (b.lo == b.hi) return a.lo <= b.lo && b.lo < a.hi;
  return a.lo < b.hi && b.lo < a.hi;
}

List<_Range> _changedRanges(List<TextOpcode> ops) {
  return [
    for (final op in ops)
      if (op.$1 != 'equal') _Range(op.$2, op.$3),
  ];
}

List<_Range> _clusters(List<_Range> ranges) {
  if (ranges.isEmpty) return const [];
  final sorted = [...ranges]..sort((a, b) => a.lo != b.lo ? a.lo - b.lo : a.hi - b.hi);
  final out = <_Range>[];
  var cur = sorted.first;
  for (var i = 1; i < sorted.length; i++) {
    final next = sorted[i];
    if (_rangesOverlap(cur, next)) {
      final lo = cur.lo < next.lo ? cur.lo : next.lo;
      final hi = cur.hi > next.hi ? cur.hi : next.hi;
      cur = _Range(lo, hi);
    } else {
      out.add(cur);
      cur = next;
    }
  }
  out.add(cur);
  return out;
}

List<String> _image(
  List<TextOpcode> ops,
  List<String> other,
  int lo,
  int hi,
) {
  final out = <String>[];
  for (final (tag, i1, i2, j1, j2) in ops) {
    if (tag == 'insert') {
      final atPoint = lo == hi && i1 == lo;
      final inside = lo != hi && i1 >= lo && i1 < hi;
      if (atPoint || inside) out.addAll(other.sublist(j1, j2));
      continue;
    }
    if (i2 <= lo || i1 >= hi) continue;
    if (tag == 'equal') {
      final from = lo > i1 ? lo - i1 : 0;
      final to = hi < i2 ? hi - i1 : i2 - i1;
      out.addAll(other.sublist(j1 + from, j1 + to));
    } else {
      out.addAll(other.sublist(j1, j2));
    }
  }
  return out;
}

bool _sameLines(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

List<String> splitMarkerParts(String raw) {
  final body = DocumentTextCodec.stripHeader(raw);
  if (body.trim().isEmpty) return const [];
  return [
    for (final part in body.split(RegExp(r'\n\n+')))
      if (part.trim().isNotEmpty) part.trim(),
  ];
}

String joinMarkerParts(List<String> parts) {
  if (parts.isEmpty) return DocumentTextCodec.empty();
  return DocumentTextCodec.wrap(parts.join('\n\n'));
}

/// 3-way merge of v4 marker parts. One-sided and identical edits apply;
/// leftover overlaps stay on [localSided] / [serverSided] for the lookalike.
ThreeWayResult threeWayMarkerText({
  required String base,
  required String local,
  required String server,
}) {
  final baseParts = splitMarkerParts(base);
  final localParts = splitMarkerParts(local);
  final serverParts = splitMarkerParts(server);
  if (_sameLines(localParts, serverParts)) {
    final text = joinMarkerParts(localParts);
    return ThreeWayResult(
      hasConflicts: false,
      merged: text,
      localSided: text,
      serverSided: text,
    );
  }
  if (_sameLines(localParts, baseParts)) {
    final text = joinMarkerParts(serverParts);
    return ThreeWayResult(
      hasConflicts: false,
      merged: text,
      localSided: text,
      serverSided: text,
    );
  }
  if (_sameLines(serverParts, baseParts)) {
    final text = joinMarkerParts(localParts);
    return ThreeWayResult(
      hasConflicts: false,
      merged: text,
      localSided: text,
      serverSided: text,
    );
  }

  final localOps = sequenceOpcodes(baseParts, localParts);
  final serverOps = sequenceOpcodes(baseParts, serverParts);
  final clusters = _clusters([
    ..._changedRanges(localOps),
    ..._changedRanges(serverOps),
  ]);

  final merged = <String>[];
  final localSided = <String>[];
  final serverSided = <String>[];
  var conflicts = false;
  var cursor = 0;

  void takeEqual(int until) {
    if (until <= cursor) return;
    final slice = baseParts.sublist(cursor, until);
    merged.addAll(slice);
    localSided.addAll(slice);
    serverSided.addAll(slice);
  }

  for (final cluster in clusters) {
    takeEqual(cluster.lo);
    final baseSlice = baseParts.sublist(cluster.lo, cluster.hi);
    final localSlice = _image(localOps, localParts, cluster.lo, cluster.hi);
    final serverSlice = _image(serverOps, serverParts, cluster.lo, cluster.hi);
    final localUnchanged = _sameLines(localSlice, baseSlice);
    final serverUnchanged = _sameLines(serverSlice, baseSlice);
    if (localUnchanged && serverUnchanged) {
      merged.addAll(baseSlice);
      localSided.addAll(baseSlice);
      serverSided.addAll(baseSlice);
    } else if (localUnchanged) {
      merged.addAll(serverSlice);
      localSided.addAll(serverSlice);
      serverSided.addAll(serverSlice);
    } else if (serverUnchanged) {
      merged.addAll(localSlice);
      localSided.addAll(localSlice);
      serverSided.addAll(localSlice);
    } else if (_sameLines(localSlice, serverSlice)) {
      merged.addAll(localSlice);
      localSided.addAll(localSlice);
      serverSided.addAll(localSlice);
    } else {
      conflicts = true;
      localSided.addAll(localSlice);
      serverSided.addAll(serverSlice);
    }
    cursor = cluster.hi;
  }
  takeEqual(baseParts.length);

  // Trailing inserts past the last base index.
  final tailLocal = _image(localOps, localParts, baseParts.length, baseParts.length);
  final tailServer = _image(serverOps, serverParts, baseParts.length, baseParts.length);
  if (tailLocal.isNotEmpty || tailServer.isNotEmpty) {
    final localUnchanged = tailLocal.isEmpty;
    final serverUnchanged = tailServer.isEmpty;
    if (localUnchanged) {
      merged.addAll(tailServer);
      localSided.addAll(tailServer);
      serverSided.addAll(tailServer);
    } else if (serverUnchanged) {
      merged.addAll(tailLocal);
      localSided.addAll(tailLocal);
      serverSided.addAll(tailLocal);
    } else if (_sameLines(tailLocal, tailServer)) {
      merged.addAll(tailLocal);
      localSided.addAll(tailLocal);
      serverSided.addAll(tailLocal);
    } else {
      conflicts = true;
      localSided.addAll(tailLocal);
      serverSided.addAll(tailServer);
    }
  }

  return ThreeWayResult(
    hasConflicts: conflicts,
    merged: joinMarkerParts(conflicts ? localSided : merged),
    localSided: joinMarkerParts(localSided),
    serverSided: joinMarkerParts(serverSided),
  );
}
