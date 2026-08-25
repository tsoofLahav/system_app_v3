/// Agent text → display blocks.
///
/// Display-only twin of `document_agent_text.py` (`parse_agent_text`). This
/// side never writes: it parses the expanded fence form the agent reads so a
/// review surface can draw a real document instead of raw markers. When the
/// agent-text format changes, that Python file leads and this one follows.
///
/// Everything records the agent-text line it came from, because pending-review
/// hunks address lines: one table row, one task and one list item are each a
/// line, so a change can be marked exactly where it happened.
library;

sealed class AgentBlock {
  const AgentBlock({required this.lineStart, required this.lineEnd});

  /// 0-based, inclusive.
  final int lineStart;

  /// 0-based, inclusive.
  final int lineEnd;

  bool coversLine(int line) => line >= lineStart && line <= lineEnd;
}

class AgentHeadingBlock extends AgentBlock {
  const AgentHeadingBlock({
    required this.level,
    required this.text,
    required super.lineStart,
    required super.lineEnd,
  });

  final int level;
  final String text;
}

class AgentParagraphBlock extends AgentBlock {
  const AgentParagraphBlock({
    required this.text,
    required super.lineStart,
    required super.lineEnd,
  });

  final String text;
}

/// A run of blank lines, or an explicit `[SPACER n="…"]`.
class AgentSpacerBlock extends AgentBlock {
  const AgentSpacerBlock({
    required this.count,
    required super.lineStart,
    required super.lineEnd,
  });

  final int count;
}

class AgentListItem {
  const AgentListItem({
    required this.text,
    required this.indent,
    required this.line,
    required this.marker,
  });

  final String text;
  final int indent;
  final int line;

  /// Rendered bullet or number, already resolved by the parser.
  final String marker;
}

class AgentListBlock extends AgentBlock {
  const AgentListBlock({
    required this.ordered,
    required this.items,
    required super.lineStart,
    required super.lineEnd,
  });

  final bool ordered;
  final List<AgentListItem> items;
}

class AgentTaskItem {
  const AgentTaskItem({
    required this.title,
    required this.done,
    required this.line,
  });

  final String title;
  final bool done;
  final int line;
}

class AgentTaskListBlock extends AgentBlock {
  const AgentTaskListBlock({
    required this.objectId,
    required this.tasks,
    required super.lineStart,
    required super.lineEnd,
    this.title = '',
  });

  final int objectId;
  final String title;
  final List<AgentTaskItem> tasks;
}

class AgentInfoBlock extends AgentBlock {
  const AgentInfoBlock({
    required this.objectId,
    required this.title,
    required this.titleLine,
    required this.bodyLines,
    required super.lineStart,
    required super.lineEnd,
  });

  final int objectId;
  final String title;

  /// -1 when the fence held only a body (legacy single-line info).
  final int titleLine;
  final List<AgentTextLine> bodyLines;
}

/// One body line that still knows where it came from.
class AgentTextLine {
  const AgentTextLine({required this.text, required this.line});

  final String text;
  final int line;
}

class AgentTableRow {
  const AgentTableRow({required this.cells, required this.line});

  final List<String> cells;
  final int line;
}

class AgentTableBlock extends AgentBlock {
  const AgentTableBlock({
    required this.objectId,
    required this.rows,
    required super.lineStart,
    required super.lineEnd,
  });

  /// Null for a legacy id-less `[TABLE]` fence.
  final int? objectId;
  final List<AgentTableRow> rows;

  int get columnCount =>
      rows.fold(0, (max, row) => row.cells.length > max ? row.cells.length : max);
}

class AgentGraphBlock extends AgentBlock {
  const AgentGraphBlock({
    required this.objectId,
    required this.chartType,
    required this.labels,
    required this.values,
    required this.colors,
    required this.labelsLine,
    required this.valuesLine,
    required this.colorsLine,
    required super.lineStart,
    required super.lineEnd,
  });

  final int objectId;
  final String chartType;
  final List<String> labels;
  final List<String> values;
  final List<String> colors;
  final int labelsLine;
  final int valuesLine;

  /// -1 when the fence carried no colour row.
  final int colorsLine;
}

class AgentImageBlock extends AgentBlock {
  const AgentImageBlock({
    required this.objectId,
    required this.caption,
    required this.url,
    this.extraPanes = const [],
    required super.lineStart,
    required super.lineEnd,
  });

  final int objectId;
  final String caption;
  final String url;
  final List<({String url, String caption})> extraPanes;
}

/// A line no rule matched — shown as-is rather than dropped.
class AgentUnknownBlock extends AgentBlock {
  const AgentUnknownBlock({
    required this.text,
    required super.lineStart,
    required super.lineEnd,
    this.isMarker = false,
  });

  final String text;

  /// A leftover structure marker. The reader must never be shown marker
  /// language, so the view draws these as a quiet rule instead of text.
  final bool isMarker;
}

final _headingRe = RegExp(r'^(#{1,6})\s*(.*)$');
final _spacerRe = RegExp(r'^\[SPACER(?:\s+n="(\d+)")?\]$', caseSensitive: false);
final _taskListOpenRe = RegExp(
  r'^\[TASK_LIST\s+id="(\d+)"(?:\s+title="([^"]*)")?\]$',
  caseSensitive: false,
);
final _infoOpenRe = RegExp(r'^\[INFO\s+id="(\d+)"\]$', caseSensitive: false);
final _tableOpenRe = RegExp(r'^\[TABLE(?:\s+id="(\d+)")?\]$', caseSensitive: false);
final _graphOpenRe = RegExp(
  r'^\[GRAPH\s+id="(\d+)"(?:\s+chartType="([^"]*)")?(?:\s+title="[^"]*")?\]$',
  caseSensitive: false,
);
final _imageRe = RegExp(
  r'^\[IMAGE\s+id="(\d+)"(?:\s+caption="([^"]*)")?(?:\s+url="([^"]*)")?(?:\s+width="([^"]*)")?\]$',
  caseSensitive: false,
);
final _imagePaneRe = RegExp(
  r'^url="([^"]*)"(?:\s+caption="([^"]*)")?(?:\s+width="([^"]*)")?$',
  caseSensitive: false,
);
final _imageCloseRe = RegExp(r'^\[/IMAGE\]$', caseSensitive: false);
final _bulletOpenRe = RegExp(r'^\[BULLET_LIST\]$', caseSensitive: false);
final _orderedOpenRe = RegExp(r'^\[ORDERED_LIST\]$', caseSensitive: false);
final _taskLineRe = RegExp(r'^-\s*\[( |x|X)\]\s*(.*)$');
final _bulletItemRe = RegExp(r'^(\s*)[-*]\s+(.*)$');
final _orderedItemRe = RegExp(r'^(\s*)\d+[.)]\s+(.*)$');

/// A marker line that no rule above understood — including the residue a
/// broken write leaves behind, where the opening `[` was already eaten
/// (`BULLET_LIST]`). Matching the name at the start keeps ordinary sentences
/// that happen to end in `]` out of this.
final _markerResidueRe = RegExp(
  r'^\[?\s*/?\s*(TASK_LIST|INFO|IMAGE|GRAPH|BULLET_LIST|ORDERED_LIST|TABLE|'
  r'SPACER|EMBED)\b[^\]]*\]$',
  caseSensitive: false,
);

/// Parse agent text into display blocks keyed to their source lines.
List<AgentBlock> parseAgentTextBlocks(String text) {
  final lines = text.isEmpty ? <String>[] : text.split('\n');
  // A trailing newline is a terminator, not an empty last line.
  if (lines.isNotEmpty && lines.last.isEmpty && text.endsWith('\n')) {
    lines.removeLast();
  }

  final blocks = <AgentBlock>[];
  var i = 0;
  while (i < lines.length) {
    final raw = lines[i];
    final line = raw.trim();

    if (line.isEmpty) {
      final start = i;
      while (i < lines.length && lines[i].trim().isEmpty) {
        i++;
      }
      blocks.add(
        AgentSpacerBlock(count: i - start, lineStart: start, lineEnd: i - 1),
      );
      continue;
    }

    final spacer = _spacerRe.firstMatch(line);
    if (spacer != null) {
      blocks.add(
        AgentSpacerBlock(
          count: int.tryParse(spacer.group(1) ?? '1') ?? 1,
          lineStart: i,
          lineEnd: i,
        ),
      );
      i++;
      continue;
    }

    final image = _imageRe.firstMatch(line);
    if (image != null) {
      var end = i;
      final extras = <({String url, String caption})>[];
      var j = i + 1;
      while (j < lines.length) {
        final t = lines[j].trim();
        if (_imageCloseRe.hasMatch(t)) {
          end = j;
          break;
        }
        final pane = _imagePaneRe.firstMatch(t);
        if (pane != null) {
          extras.add((url: pane.group(1) ?? '', caption: pane.group(2) ?? ''));
          j++;
          continue;
        }
        extras.clear();
        end = i;
        break;
      }
      if (end == i) extras.clear();
      blocks.add(
        AgentImageBlock(
          objectId: int.parse(image.group(1)!),
          caption: image.group(2) ?? '',
          url: image.group(3) ?? '',
          extraPanes: extras,
          lineStart: i,
          lineEnd: end,
        ),
      );
      i = end + 1;
      continue;
    }

    final taskOpen = _taskListOpenRe.firstMatch(line);
    if (taskOpen != null) {
      i = _readTaskList(
        lines,
        i,
        int.parse(taskOpen.group(1)!),
        taskOpen.group(2) ?? '',
        blocks,
      );
      continue;
    }

    final infoOpen = _infoOpenRe.firstMatch(line);
    if (infoOpen != null) {
      i = _readInfo(lines, i, int.parse(infoOpen.group(1)!), blocks);
      continue;
    }

    final graphOpen = _graphOpenRe.firstMatch(line);
    if (graphOpen != null) {
      i = _readGraph(
        lines,
        i,
        int.parse(graphOpen.group(1)!),
        graphOpen.group(2) ?? '',
        blocks,
      );
      continue;
    }

    final tableOpen = _tableOpenRe.firstMatch(line);
    if (tableOpen != null) {
      final id = tableOpen.group(1);
      i = _readTable(lines, i, id == null ? null : int.parse(id), blocks);
      continue;
    }

    if (_bulletOpenRe.hasMatch(line)) {
      i = _readList(lines, i, ordered: false, blocks: blocks);
      continue;
    }
    if (_orderedOpenRe.hasMatch(line)) {
      i = _readList(lines, i, ordered: true, blocks: blocks);
      continue;
    }

    final heading = _headingRe.firstMatch(line);
    if (heading != null) {
      blocks.add(
        AgentHeadingBlock(
          level: heading.group(1)!.length.clamp(1, 6),
          text: heading.group(2)!.trim(),
          lineStart: i,
          lineEnd: i,
        ),
      );
      i++;
      continue;
    }

    if (_markerResidueRe.hasMatch(line)) {
      blocks.add(
        AgentUnknownBlock(
          text: line,
          lineStart: i,
          lineEnd: i,
          isMarker: true,
        ),
      );
      i++;
      continue;
    }

    // Item lines with no fence around them — a write that lost its markers.
    // They are a list to the reader, so they are drawn as one.
    if (_looseItemMatch(line) != null) {
      i = _readLooseList(lines, i, blocks);
      continue;
    }

    blocks.add(AgentParagraphBlock(text: raw, lineStart: i, lineEnd: i));
    i++;
  }

  return blocks;
}

/// A bullet or numbered item standing outside any fence, or null.
RegExpMatch? _looseItemMatch(String line) {
  if (_taskLineRe.hasMatch(line)) return null;
  return _bulletItemRe.firstMatch(line) ?? _orderedItemRe.firstMatch(line);
}

int _readLooseList(List<String> lines, int start, List<AgentBlock> blocks) {
  final ordered = _orderedItemRe.hasMatch(lines[start].trim());
  final items = <AgentListItem>[];
  var number = 1;
  var i = start;
  while (i < lines.length) {
    final line = lines[i].trim();
    final match = _looseItemMatch(line);
    if (match == null) break;
    if (_orderedItemRe.hasMatch(line) != ordered) break;
    items.add(
      AgentListItem(
        text: match.group(2)!,
        indent: match.group(1)!.length ~/ 2,
        line: i,
        marker: ordered ? '${number++}.' : '•',
      ),
    );
    i++;
  }
  blocks.add(
    AgentListBlock(
      ordered: ordered,
      items: items,
      lineStart: start,
      lineEnd: i - 1,
    ),
  );
  return i;
}

/// Index of the closing marker, or -1 when the fence never closes.
int _findCloser(List<String> lines, int from, String closer) {
  for (var i = from; i < lines.length; i++) {
    if (lines[i].trim().toUpperCase() == closer) return i;
  }
  return -1;
}

int _readTaskList(
  List<String> lines,
  int open,
  int objectId,
  String title,
  List<AgentBlock> blocks,
) {
  final close = _findCloser(lines, open + 1, '[/TASK_LIST]');
  final end = close == -1 ? lines.length - 1 : close;
  final tasks = <AgentTaskItem>[];
  for (var i = open + 1; i < (close == -1 ? lines.length : close); i++) {
    final line = lines[i].trim();
    if (line.isEmpty) continue;
    final upper = line.toUpperCase();
    if (upper == 'ACTIVE:' || upper == 'DONE:') continue;
    final match = _taskLineRe.firstMatch(line);
    if (match == null) continue;
    tasks.add(
      AgentTaskItem(
        title: match.group(2)!,
        done: match.group(1)!.toLowerCase() == 'x',
        line: i,
      ),
    );
  }
  blocks.add(
    AgentTaskListBlock(
      objectId: objectId,
      title: title,
      tasks: tasks,
      lineStart: open,
      lineEnd: end,
    ),
  );
  return end + 1;
}

int _readInfo(
  List<String> lines,
  int open,
  int objectId,
  List<AgentBlock> blocks,
) {
  final close = _findCloser(lines, open + 1, '[/INFO]');
  final end = close == -1 ? lines.length - 1 : close;
  final content = <AgentTextLine>[];
  for (var i = open + 1; i < (close == -1 ? lines.length : close); i++) {
    content.add(AgentTextLine(text: lines[i], line: i));
  }
  // Frozen shape: first line is the title, the rest is body. A single line is
  // legacy body-only, so it must not be promoted to a title.
  final hasTitle = content.length > 1;
  blocks.add(
    AgentInfoBlock(
      objectId: objectId,
      title: hasTitle ? content.first.text.trim() : '',
      titleLine: hasTitle ? content.first.line : -1,
      bodyLines: hasTitle ? content.sublist(1) : content,
      lineStart: open,
      lineEnd: end,
    ),
  );
  return end + 1;
}

int _readTable(
  List<String> lines,
  int open,
  int? objectId,
  List<AgentBlock> blocks,
) {
  final close = _findCloser(lines, open + 1, '[/TABLE]');
  final end = close == -1 ? lines.length - 1 : close;
  final rows = <AgentTableRow>[];
  for (var i = open + 1; i < (close == -1 ? lines.length : close); i++) {
    if (lines[i].trim().isEmpty) continue;
    rows.add(AgentTableRow(cells: splitAgentRow(lines[i]), line: i));
  }
  blocks.add(
    AgentTableBlock(
      objectId: objectId,
      rows: rows,
      lineStart: open,
      lineEnd: end,
    ),
  );
  return end + 1;
}

int _readGraph(
  List<String> lines,
  int open,
  int objectId,
  String chartType,
  List<AgentBlock> blocks,
) {
  final close = _findCloser(lines, open + 1, '[/GRAPH]');
  final end = close == -1 ? lines.length - 1 : close;
  final rows = <AgentTableRow>[];
  for (var i = open + 1; i < (close == -1 ? lines.length : close); i++) {
    if (lines[i].trim().isEmpty) continue;
    rows.add(AgentTableRow(cells: splitAgentRow(lines[i]), line: i));
  }
  blocks.add(
    AgentGraphBlock(
      objectId: objectId,
      chartType: chartType,
      labels: rows.isNotEmpty ? rows[0].cells : const [],
      values: rows.length > 1 ? rows[1].cells : const [],
      colors: rows.length > 2 ? rows[2].cells : const [],
      labelsLine: rows.isNotEmpty ? rows[0].line : -1,
      valuesLine: rows.length > 1 ? rows[1].line : -1,
      colorsLine: rows.length > 2 ? rows[2].line : -1,
      lineStart: open,
      lineEnd: end,
    ),
  );
  return end + 1;
}

int _readList(
  List<String> lines,
  int open, {
  required bool ordered,
  required List<AgentBlock> blocks,
}) {
  final closer = ordered ? '[/ORDERED_LIST]' : '[/BULLET_LIST]';
  final close = _findCloser(lines, open + 1, closer);
  final end = close == -1 ? lines.length - 1 : close;
  final items = <AgentListItem>[];
  var number = 1;
  for (var i = open + 1; i < (close == -1 ? lines.length : close); i++) {
    final line = lines[i];
    if (line.trim().isEmpty) continue;
    final match =
        ordered ? _orderedItemRe.firstMatch(line) : _bulletItemRe.firstMatch(line);
    if (match == null) continue;
    final indent = match.group(1)!.length ~/ 2;
    items.add(
      AgentListItem(
        text: match.group(2)!,
        indent: indent,
        line: i,
        marker: ordered ? '${number++}.' : '•',
      ),
    );
  }
  blocks.add(
    AgentListBlock(
      ordered: ordered,
      items: items,
      lineStart: open,
      lineEnd: end,
    ),
  );
  return end + 1;
}

/// Split a table/graph row on the two visible characters `\t`.
///
/// Mirrors `_split_table_row`: `\\t` is a literal backslash-t inside a cell,
/// `\\` a literal backslash, and a raw tab still separates older text.
List<String> splitAgentRow(String line) {
  final cells = <String>[];
  final current = StringBuffer();
  var i = 0;
  while (i < line.length) {
    if (line[i] == r'\' && i + 1 < line.length && line[i + 1] == r'\') {
      if (i + 2 < line.length && line[i + 2] == 't') {
        current.write('\t');
        i += 3;
        continue;
      }
      current.write(r'\');
      i += 2;
      continue;
    }
    if (line[i] == r'\' && i + 1 < line.length && line[i + 1] == 't') {
      cells.add(current.toString());
      current.clear();
      i += 2;
      continue;
    }
    if (line[i] == '\t') {
      cells.add(current.toString());
      current.clear();
      i++;
      continue;
    }
    current.write(line[i]);
    i++;
  }
  cells.add(current.toString());
  return cells;
}
