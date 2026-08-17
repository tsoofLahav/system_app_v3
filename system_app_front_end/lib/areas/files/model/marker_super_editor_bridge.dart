/// Marker-text (v4) ↔ Super Editor [MutableDocument] bridge.
///
/// Disk SoT stays marker text; Super Editor is the runtime editing surface.
library;

import 'package:flutter/foundation.dart';
import 'package:super_editor/super_editor.dart';

import './document_text_codec.dart';
import './object_embed_node.dart';

/// Convert wrapped or bare editor text into a Super Editor document.
MutableDocument markerTextToMutableDocument(String? raw) {
  final body = DocumentTextCodec.stripHeader(raw ?? '').trim();
  if (body.isEmpty) {
    return MutableDocument(
      nodes: [
        ParagraphNode(id: Editor.createNodeId(), text: AttributedText()),
      ],
    );
  }

  final nodes = <DocumentNode>[];
  final parts = body.split(RegExp(r'\n\n+'));
  for (final part in parts) {
    final trimmed = part.trim();
    if (trimmed.isEmpty) continue;
    final info = DocumentTextCodec.classifyTopLevel(trimmed);
    switch (info.kind) {
      case MarkerPartKind.embed:
        final oid = info.objectId ?? 0;
        nodes.add(
          ObjectEmbedNode(
            id: ObjectEmbedNode.idFor(oid),
            objectId: oid,
            objectType: info.objectType ?? 'embed',
          ),
        );
      case MarkerPartKind.spacer:
        nodes.add(
          ParagraphNode(id: Editor.createNodeId(), text: AttributedText()),
        );
      case MarkerPartKind.bulletList:
        nodes.addAll(_listItemsFromBody(info.listBody ?? '', ordered: false));
      case MarkerPartKind.orderedList:
        nodes.addAll(_listItemsFromBody(info.listBody ?? '', ordered: true));
      case MarkerPartKind.table:
        // Legacy structure fence — caller migrates to a table object.
        nodes.add(
          LegacyTableFenceNode(
            id: Editor.createNodeId(),
            rows: _parseTableRows(info.tableBody ?? ''),
          ),
        );
      case MarkerPartKind.heading:
        final heading = DocumentTextCodec.headingRe.firstMatch(trimmed);
        final level = (info.headingLevel ?? heading?.group(1)?.length ?? 1)
            .clamp(1, 6);
        final text = heading?.group(2) ?? '';
        nodes.add(
          ParagraphNode(
            id: Editor.createNodeId(),
            text: AttributedText(text),
            metadata: {'blockType': _headerAttribution(level)},
          ),
        );
      case MarkerPartKind.paragraph:
        nodes.add(
          ParagraphNode(
            id: Editor.createNodeId(),
            text: AttributedText(part),
          ),
        );
    }
  }

  if (nodes.isEmpty) {
    nodes.add(ParagraphNode(id: Editor.createNodeId(), text: AttributedText()));
  }
  // File ending on an embed needs a writable paragraph below (Enter-to-exit).
  if (nodes.last is ObjectEmbedNode) {
    nodes.add(ParagraphNode(id: Editor.createNodeId(), text: AttributedText()));
  }
  return MutableDocument(nodes: nodes);
}

/// Serialize a Super Editor document to wrapped v4 marker text.
String mutableDocumentToMarkerText(Document document) {
  final lines = <String>[];
  var i = 0;
  final nodeCount = document.nodeCount;

  while (i < nodeCount) {
    final node = document.getNodeAt(i);
    if (node == null) {
      i++;
      continue;
    }

    if (node is ObjectEmbedNode) {
      lines.add(
        DocumentTextCodec.pointerLine(node.objectId, node.objectType),
      );
      i++;
      continue;
    }

    if (node is LegacyTableFenceNode) {
      final rowLines = [
        for (final row in node.rows)
          row.map(_escapeCell).join('\t'),
      ];
      if (rowLines.isNotEmpty) {
        lines.add('[TABLE]\n${rowLines.join('\n')}\n[/TABLE]');
      }
      i++;
      continue;
    }

    if (node is ListItemNode) {
      final ordered = node.type == ListItemType.ordered;
      final items = <ListItemNode>[node];
      var j = i + 1;
      while (j < nodeCount) {
        final next = document.getNodeAt(j);
        if (next is! ListItemNode) break;
        if ((next.type == ListItemType.ordered) != ordered) break;
        items.add(next);
        j++;
      }
      final tag = ordered ? 'ORDERED_LIST' : 'BULLET_LIST';
      final body = [
        for (var k = 0; k < items.length; k++)
          _listItemLine(items[k], k, ordered: ordered),
      ].join('\n');
      if (body.isNotEmpty) {
        lines.add('[$tag]\n$body\n[/$tag]');
      }
      i = j;
      continue;
    }

    if (node is ParagraphNode) {
      final blockType = node.getMetadataValue('blockType');
      final level = _headingLevel(blockType);
      final text = node.text.toPlainText();
      if (level != null) {
        lines.add('${'#' * level} $text'.trimRight());
      } else if (text.trim().isEmpty) {
        // A blank line the user made is content: it is kept wherever it sits,
        // including at the end of the file, so an object inserted there lands
        // after the gap instead of jumping up under the last text. Only blanks
        // before any content are dropped — a file cannot start on air, and a
        // brand new file is one empty paragraph.
        if (lines.isNotEmpty) {
          lines.add('[SPACER n="1"]');
        }
      } else {
        lines.add(text);
      }
      i++;
      continue;
    }

    // Unknown node types — skip.
    i++;
  }

  if (lines.isEmpty) return DocumentTextCodec.empty();
  return DocumentTextCodec.wrap(lines.join('\n\n'));
}

/// Map a Super Editor node index to a top-level marker-part insert gap.
///
/// Consecutive [ListItemNode]s of the same type collapse to one fence part.
int markerGapIndexForNodeIndex(Document document, int nodeIndex) {
  var gap = 0;
  var i = 0;
  final n = document.nodeCount;
  final target = nodeIndex.clamp(0, n);
  while (i < target) {
    final node = document.getNodeAt(i);
    if (node == null) {
      i++;
      continue;
    }
    if (node is ListItemNode) {
      final ordered = node.type == ListItemType.ordered;
      var j = i + 1;
      while (j < n) {
        final next = document.getNodeAt(j);
        if (next is! ListItemNode) break;
        if ((next.type == ListItemType.ordered) != ordered) break;
        j++;
      }
      gap++;
      i = j;
      continue;
    }
    gap++;
    i++;
  }
  return gap;
}

/// True when [document] still contains unmigrated table fences.
bool documentHasLegacyTableFences(Document document) {
  for (var i = 0; i < document.nodeCount; i++) {
    if (document.getNodeAt(i) is LegacyTableFenceNode) return true;
  }
  return false;
}

List<LegacyTableFenceNode> legacyTableFencesIn(Document document) {
  final out = <LegacyTableFenceNode>[];
  for (var i = 0; i < document.nodeCount; i++) {
    final n = document.getNodeAt(i);
    if (n is LegacyTableFenceNode) out.add(n);
  }
  return out;
}

NamedAttribution _headerAttribution(int level) => switch (level) {
      1 => header1Attribution,
      2 => header2Attribution,
      3 => header3Attribution,
      4 => header4Attribution,
      5 => header5Attribution,
      _ => header6Attribution,
    };

int? _headingLevel(Object? blockType) {
  if (blockType == header1Attribution) return 1;
  if (blockType == header2Attribution) return 2;
  if (blockType == header3Attribution) return 3;
  if (blockType == header4Attribution) return 4;
  if (blockType == header5Attribution) return 5;
  if (blockType == header6Attribution) return 6;
  return null;
}

List<ListItemNode> _listItemsFromBody(String body, {required bool ordered}) {
  final items = <ListItemNode>[];
  final itemRe = ordered
      ? RegExp(r'^(\s*)\d+[\.\)]\s+(.*)$')
      : RegExp(r'^(\s*)[-*]\s+(.*)$');
  for (final line in body.split('\n')) {
    final m = itemRe.firstMatch(line);
    if (m == null) continue;
    final spaces = m.group(1)?.length ?? 0;
    final text = m.group(2) ?? '';
    items.add(
      ordered
          ? ListItemNode.ordered(
              id: Editor.createNodeId(),
              text: AttributedText(text),
              indent: spaces ~/ 2,
            )
          : ListItemNode.unordered(
              id: Editor.createNodeId(),
              text: AttributedText(text),
              indent: spaces ~/ 2,
            ),
    );
  }
  if (items.isEmpty) {
    items.add(
      ordered
          ? ListItemNode.ordered(
              id: Editor.createNodeId(),
              text: AttributedText(),
            )
          : ListItemNode.unordered(
              id: Editor.createNodeId(),
              text: AttributedText(),
            ),
    );
  }
  return items;
}

String _listItemLine(ListItemNode item, int index, {required bool ordered}) {
  final indent = '  ' * item.indent;
  final text = item.text.toPlainText();
  if (ordered) return '$indent${index + 1}. $text';
  return '$indent- $text';
}

List<List<String>> _parseTableRows(String body) {
  final rows = <List<String>>[];
  for (final line in body.split('\n')) {
    if (line.trim().isEmpty) continue;
    rows.add([
      for (final cell in line.split('\t'))
        cell.replaceAll(r'\t', '\t').replaceAll(r'\\', r'\'),
    ]);
  }
  if (rows.isEmpty) {
    rows.add(['', '']);
  }
  return rows;
}

String _escapeCell(String text) =>
    text.replaceAll(r'\', r'\\').replaceAll('\t', r'\t');

/// Temporary node for unmigrated `[TABLE]…[/TABLE]` fences.
@immutable
class LegacyTableFenceNode extends BlockNode {
  LegacyTableFenceNode({
    required this.id,
    required this.rows,
    super.metadata,
  }) {
    initAddToMetadata({
      'blockType': const NamedAttribution('legacyTableFence'),
    });
  }

  @override
  final String id;
  final List<List<String>> rows;

  @override
  String? copyContent(NodeSelection selection) => null;

  @override
  bool hasEquivalentContent(DocumentNode other) =>
      other is LegacyTableFenceNode && listEquals(other.rows, rows);

  @override
  DocumentNode copyWithAddedMetadata(Map<String, dynamic> newProperties) {
    return LegacyTableFenceNode(
      id: id,
      rows: rows,
      metadata: {...metadata, ...newProperties},
    );
  }

  @override
  DocumentNode copyAndReplaceMetadata(Map<String, dynamic> newMetadata) {
    return LegacyTableFenceNode(id: id, rows: rows, metadata: newMetadata);
  }
}
