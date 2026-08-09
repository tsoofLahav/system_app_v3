/// v4 marker-text document (source of truth). See editor/DOCUMENT_TEXT.md.
library;

import './document_model.dart';
import './document_codec.dart';

/// Classification of one top-level `\n\n`-separated slice (shared by parse + buffer).
enum MarkerPartKind {
  paragraph,
  heading,
  bulletList,
  orderedList,
  table,
  embed,
  spacer,
}

class MarkerPartInfo {
  const MarkerPartInfo(
    this.kind, {
    this.objectId,
    this.objectType,
    this.headingLevel,
    this.listBody,
    this.tableBody,
  });

  final MarkerPartKind kind;
  final int? objectId;
  final String? objectType;
  final int? headingLevel;
  final String? listBody;
  final String? tableBody;
}

class DocumentTextCodec {
  static const header = '%%system_app_document v4';

  static final pointerRe = RegExp(
    r'^\[(INFO|TASK_LIST|IMAGE|GRAPH|EMBED)\s+id="(\d+)"\s*\]\s*$',
    caseSensitive: false,
  );
  static final _pointerAnyRe = RegExp(
    r'\[(INFO|TASK_LIST|IMAGE|GRAPH|EMBED)\s+id="(\d+)"\s*\]',
    caseSensitive: false,
  );
  static final spacerRe = RegExp(
    r'^\[SPACER(?:\s+n="(\d+)")?\s*\]\s*$',
    caseSensitive: false,
  );
  static final _bulletFenceRe = RegExp(
    r'^\[BULLET_LIST\]\s*([\s\S]*?)\s*\[/BULLET_LIST\]\s*$',
    caseSensitive: false,
  );
  static final _orderedFenceRe = RegExp(
    r'^\[ORDERED_LIST\]\s*([\s\S]*?)\s*\[/ORDERED_LIST\]\s*$',
    caseSensitive: false,
  );
  static final _tableFenceRe = RegExp(
    r'^\[TABLE\]\s*([\s\S]*?)\s*\[/TABLE\]\s*$',
    caseSensitive: false,
  );
  static final headingRe = RegExp(r'^(#{1,6})\s+(.*)$');

  /// Classify a trimmed top-level part for indexing / parse.
  static MarkerPartInfo classifyTopLevel(String trimmed) {
    final pointer = pointerRe.firstMatch(trimmed);
    if (pointer != null) {
      return MarkerPartInfo(
        MarkerPartKind.embed,
        objectId: int.parse(pointer.group(2)!),
        objectType: objectTypeForTag(pointer.group(1)!),
      );
    }
    if (spacerRe.hasMatch(trimmed)) {
      return const MarkerPartInfo(MarkerPartKind.spacer);
    }
    final bullet = _bulletFenceRe.firstMatch(trimmed);
    if (bullet != null) {
      return MarkerPartInfo(MarkerPartKind.bulletList, listBody: bullet.group(1));
    }
    final ordered = _orderedFenceRe.firstMatch(trimmed);
    if (ordered != null) {
      return MarkerPartInfo(MarkerPartKind.orderedList, listBody: ordered.group(1));
    }
    final table = _tableFenceRe.firstMatch(trimmed);
    if (table != null) {
      return MarkerPartInfo(MarkerPartKind.table, tableBody: table.group(1));
    }
    final heading = headingRe.firstMatch(trimmed.split('\n').first);
    if (heading != null && !trimmed.contains('\n')) {
      return MarkerPartInfo(
        MarkerPartKind.heading,
        headingLevel: heading.group(1)!.length,
      );
    }
    return const MarkerPartInfo(MarkerPartKind.paragraph);
  }

  static String? objectTypeForTag(String tag) => switch (tag.toUpperCase()) {
        'INFO' => 'info',
        'TASK_LIST' => 'task_list',
        'IMAGE' => 'image',
        'GRAPH' => 'graph',
        _ => null,
      };

  static bool isEditorText(String? raw) {
    final body = raw?.trimLeft() ?? '';
    return body.startsWith(header);
  }

  static String stripHeader(String raw) {
    if (!isEditorText(raw)) return raw;
    final idx = raw.indexOf('\n');
    return idx < 0 ? '' : raw.substring(idx + 1);
  }

  static String wrap(String body) {
    final bare = isEditorText(body) ? stripHeader(body) : body;
    return '$header\n$bare';
  }

  static String empty() => wrap('');

  static String pointerLine(int objectId, [String? objectType]) {
    final tag = switch (objectType) {
      'info' => 'INFO',
      'task_list' => 'TASK_LIST',
      'image' => 'IMAGE',
      'graph' => 'GRAPH',
      _ => 'EMBED',
    };
    return '[$tag id="$objectId"]';
  }

  /// Serialize in-memory blocks to wrapped editor text (spans dropped).
  static String serialize(
    RichDocument doc, {
    Map<int, String>? objectTypes,
  }) {
    final lines = <String>[];
    for (final block in doc.blocks) {
      if (block is ParagraphNode) {
        _appendParagraph(lines, block.text);
      } else if (block is HeadingNode) {
        final level = block.level.clamp(1, 6);
        lines.add('${'#' * level} ${block.text}'.trimRight());
      } else if (block is ListNode) {
        final tag =
            block.listStyle == 'numbered' ? 'ORDERED_LIST' : 'BULLET_LIST';
        final items = <String>[
          for (var i = 0; i < block.items.length; i++)
            _listItemLine(block, i),
        ];
        if (items.isNotEmpty) {
          lines.add('[$tag]\n${items.join('\n')}\n[/$tag]');
        }
      } else if (block is TableNode) {
        final rows = [
          for (final row in block.rows)
            row.map((c) => _escapeCell(c.text)).join('\t'),
        ];
        if (rows.isNotEmpty) {
          lines.add('[TABLE]\n${rows.join('\n')}\n[/TABLE]');
        }
      } else if (block is EmbedNode) {
        final type = objectTypes?[block.objectId] ?? block.objectType;
        lines.add(pointerLine(block.objectId, type));
      }
    }
    if (lines.isEmpty) return empty();
    if (lines.every((l) => spacerRe.hasMatch(l.trim()))) return empty();
    return wrap(lines.join('\n\n'));
  }

  /// Parse wrapped or bare editor text into a RichDocument (view model).
  static RichDocument parse(String? raw) {
    final body = stripHeader(raw ?? '').trim();
    if (body.isEmpty) {
      return RichDocument(
        version: RichDocument.documentVersion,
        blocks: [ParagraphNode(id: DocumentCodec.newId('b'), text: '')],
      );
    }
    final blocks = <DocumentNode>[];
    final parts = body.split(RegExp(r'\n\n+'));
    for (final part in parts) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      final info = classifyTopLevel(trimmed);
      switch (info.kind) {
        case MarkerPartKind.embed:
          blocks.add(
            EmbedNode(
              id: DocumentCodec.newId('b'),
              objectId: info.objectId ?? 0,
              objectType: info.objectType,
            ),
          );
        case MarkerPartKind.spacer:
          blocks.add(ParagraphNode(id: DocumentCodec.newId('b'), text: ''));
        case MarkerPartKind.bulletList:
          blocks.add(_parseList(info.listBody ?? '', ordered: false));
        case MarkerPartKind.orderedList:
          blocks.add(_parseList(info.listBody ?? '', ordered: true));
        case MarkerPartKind.table:
          blocks.add(_parseTable(info.tableBody ?? ''));
        case MarkerPartKind.heading:
          final heading = headingRe.firstMatch(trimmed);
          blocks.add(
            HeadingNode(
              id: DocumentCodec.newId('b'),
              level: info.headingLevel ?? heading?.group(1)?.length ?? 1,
              text: heading?.group(2) ?? '',
            ),
          );
        case MarkerPartKind.paragraph:
          blocks.add(ParagraphNode(id: DocumentCodec.newId('b'), text: part));
      }
    }
    if (blocks.isEmpty) {
      blocks.add(ParagraphNode(id: DocumentCodec.newId('b'), text: ''));
    }
    return RichDocument(version: RichDocument.documentVersion, blocks: blocks);
  }

  /// String-level pointer move (tests / migrate). Editor uses [DocumentBuffer].
  static String movePointerInText(
    String wrapped, {
    required int objectId,
    required int gapIndex,
  }) {
    final body = stripHeader(wrapped);
    final parts = body.isEmpty
        ? <String>[]
        : body.split(RegExp(r'\n\n+')).where((p) => p.isNotEmpty).toList();
    final current = parts.indexWhere((p) {
      final m = pointerRe.firstMatch(p.trim());
      return m != null && int.parse(m.group(2)!) == objectId;
    });
    if (current < 0) return wrap(body);
    // Already sitting in this gap.
    if (gapIndex == current || gapIndex == current + 1) return wrap(body);
    final pointer = parts.removeAt(current).trim();
    var gap = gapIndex;
    if (current < gap) gap -= 1;
    gap = gap.clamp(0, parts.length);
    parts.insert(gap, pointer);
    return wrap(parts.join('\n\n'));
  }

  /// String-level split insert (tests / migrate). Editor uses [DocumentBuffer].
  static String splitPartAndInsertPointer(
    String wrapped, {
    required int partIndex,
    required int cut,
    required String pointer,
    required int removeObjectId,
  }) {
    final body = stripHeader(wrapped);
    final parts = body.isEmpty
        ? <String>[]
        : body.split(RegExp(r'\n\n+')).where((p) => p.isNotEmpty).toList();
    parts.removeWhere((p) {
      final m = pointerRe.firstMatch(p.trim());
      return m != null && int.parse(m.group(2)!) == removeObjectId;
    });
    if (partIndex < 0 || partIndex >= parts.length) {
      return movePointerInText(
        wrap(parts.isEmpty ? pointer : '${parts.join('\n\n')}\n\n$pointer'),
        objectId: removeObjectId,
        gapIndex: partIndex.clamp(0, parts.length),
      );
    }
    final part = parts[partIndex];
    var beforeEnd = cut.clamp(0, part.length);
    var afterStart = beforeEnd;
    while (beforeEnd > 0 && part[beforeEnd - 1] == '\n') {
      beforeEnd--;
    }
    while (afterStart < part.length && part[afterStart] == '\n') {
      afterStart++;
    }
    final before = part.substring(0, beforeEnd);
    final after = part.substring(afterStart);
    final next = <String>[];
    for (var i = 0; i < parts.length; i++) {
      if (i != partIndex) {
        next.add(parts[i]);
        continue;
      }
      if (before.isNotEmpty) next.add(before);
      next.add(pointer);
      if (after.isNotEmpty) next.add(after);
    }
    return wrap(next.join('\n\n'));
  }

  static Set<int> embedIds(String wrapped) => {
        for (final m in _pointerAnyRe.allMatches(stripHeader(wrapped)))
          int.parse(m.group(2)!),
      };

  static void _appendParagraph(List<String> lines, String text) {
    if (text.isEmpty) {
      lines.add('[SPACER n="1"]');
      return;
    }
    final parts = text.split('\n\n');
    var pendingEmpty = 0;
    var seenText = false;
    for (final part in parts) {
      if (part.trim().isEmpty) {
        pendingEmpty++;
        continue;
      }
      if (seenText) {
        lines.add('[SPACER n="${(2 * pendingEmpty + 1).clamp(1, 12)}"]');
        pendingEmpty = 0;
      } else if (pendingEmpty > 0) {
        lines.add('[SPACER n="${pendingEmpty.clamp(1, 12)}"]');
        pendingEmpty = 0;
      }
      lines.add(part);
      seenText = true;
    }
    if (pendingEmpty > 0) {
      lines.add('[SPACER n="${pendingEmpty.clamp(1, 12)}"]');
    }
  }

  static String _listItemLine(ListNode block, int i) {
    final item = block.items[i];
    final indent = '  ' * item.indent;
    if (block.listStyle == 'numbered') {
      return '$indent${i + 1}. ${item.text}';
    }
    return '$indent- ${item.text}';
  }

  static String _escapeCell(String text) =>
      text.replaceAll(r'\', r'\\').replaceAll('\t', r'\t');

  static ListNode _parseList(String body, {required bool ordered}) {
    final items = <ListItem>[];
    final itemRe = ordered
        ? RegExp(r'^(\s*)\d+[\.\)]\s+(.*)$')
        : RegExp(r'^(\s*)[-*]\s+(.*)$');
    for (final line in body.split('\n')) {
      final m = itemRe.firstMatch(line);
      if (m == null) continue;
      final spaces = m.group(1)?.length ?? 0;
      items.add(
        ListItem(
          id: DocumentCodec.newId('li'),
          text: m.group(2) ?? '',
          indent: spaces ~/ 2,
        ),
      );
    }
    if (items.isEmpty) {
      items.add(ListItem(id: DocumentCodec.newId('li'), text: ''));
    }
    return ListNode(
      id: DocumentCodec.newId('b'),
      listStyle: ordered ? 'numbered' : 'bullet',
      items: items,
    );
  }

  static TableNode _parseTable(String body) {
    final rows = <List<DocumentTableCell>>[];
    for (final line in body.split('\n')) {
      if (line.trim().isEmpty) continue;
      rows.add([
        for (final cell in line.split('\t'))
          DocumentTableCell(text: cell.replaceAll(r'\t', '\t').replaceAll(r'\\', r'\')),
      ]);
    }
    if (rows.isEmpty) {
      rows.add([
        const DocumentTableCell(text: ''),
        const DocumentTableCell(text: ''),
      ]);
    }
    return TableNode(id: DocumentCodec.newId('b'), rows: rows);
  }
}
