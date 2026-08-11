/// Removing structures that a delete emptied completely.
///
/// Marking a whole bullet, a whole row, a whole embed, or a whole table and
/// deleting must remove it — leaving a blank bullet or an empty row behind
/// would not match what the user marked. A part only counts here when it was
/// marked end to end.
library;

import '../model/document_codec.dart';
import '../model/document_model.dart';
import './document_text_flow.dart';

class PruneResult {
  const PruneResult({
    required this.blocks,
    required this.changed,
    required this.firstRemovedIndex,
  });

  final List<DocumentNode> blocks;
  final bool changed;

  /// Index the first removed block occupied, so the caret has somewhere to land
  /// when the part holding it is gone.
  final int firstRemovedIndex;
}

  /// Drops every bullet, row, embed, and block that [fullyEmptied] covers in full.
///
/// [spansParts] tells whether the delete crossed part boundaries. A paragraph
/// swallowed by a larger marking goes with it, but a paragraph marked on its own
/// only becomes empty — matching a word processor, where selecting a line and
/// deleting leaves the line behind.
PruneResult pruneFullyMarkedStructures({
  required List<DocumentNode> blocks,
  required Set<String> fullyEmptied,
  required bool spansParts,
}) {
  if (fullyEmptied.isEmpty) {
    return PruneResult(
      blocks: blocks,
      changed: false,
      firstRemovedIndex: blocks.length,
    );
  }

  final result = [...blocks];
  var changed = false;
  var firstRemovedIndex = blocks.length;

  for (var i = result.length - 1; i >= 0; i--) {
    final block = result[i];

    if (block is ListNode) {
      final kept = <ListItem>[];
      for (var k = 0; k < block.items.length; k++) {
        if (!fullyEmptied.contains(listItemSegmentId(block.id, k))) {
          kept.add(block.items[k]);
        }
      }
      if (kept.length == block.items.length) continue;
      if (kept.isEmpty) {
        result.removeAt(i);
        firstRemovedIndex = i;
      } else {
        result[i] = block.copyWith(items: kept);
      }
      changed = true;
    } else if (block is TableNode) {
      final kept = <List<DocumentTableCell>>[];
      for (var r = 0; r < block.rows.length; r++) {
        final row = block.rows[r];
        // A row goes only when every one of its cells was marked in full.
        var wholeRow = row.isNotEmpty;
        for (var c = 0; c < row.length; c++) {
          if (!fullyEmptied.contains(tableCellSegmentId(block.id, r, c))) {
            wholeRow = false;
            break;
          }
        }
        if (!wholeRow) kept.add(row);
      }
      if (kept.length == block.rows.length) continue;
      if (kept.isEmpty) {
        result.removeAt(i);
        firstRemovedIndex = i;
      } else {
        result[i] = block.copyWith(rows: kept);
      }
      changed = true;
    } else if (spansParts &&
        (block is ParagraphNode || block is HeadingNode) &&
        fullyEmptied.contains(paragraphSegmentId(block.id))) {
      result.removeAt(i);
      firstRemovedIndex = i;
      changed = true;
    } else if (block is EmbedNode && _embedFullyEmptied(block.id, fullyEmptied)) {
      result.removeAt(i);
      firstRemovedIndex = i;
      changed = true;
    }
  }

  if (!changed) {
    return PruneResult(
      blocks: blocks,
      changed: false,
      firstRemovedIndex: blocks.length,
    );
  }

  // A file always has somewhere to type.
  if (result.isEmpty) {
    result.add(ParagraphNode(id: DocumentCodec.newId('b'), text: ''));
  }

  return PruneResult(
    blocks: result,
    changed: true,
    firstRemovedIndex: firstRemovedIndex,
  );
}

/// Atomic `#embed` units, unified info text, or legacy title+body both cleared.
bool _embedFullyEmptied(String blockId, Set<String> fullyEmptied) {
  if (fullyEmptied.contains(embedSegmentId(blockId))) return true;
  if (fullyEmptied.contains(infoTextSegmentId(blockId))) return true;
  return fullyEmptied.contains(infoTitleSegmentId(blockId)) &&
      fullyEmptied.contains(infoBodySegmentId(blockId));
}
