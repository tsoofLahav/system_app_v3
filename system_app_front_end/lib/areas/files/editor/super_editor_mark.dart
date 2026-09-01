import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

import '../../../shared/utils/platform_text.dart';
import '../model/line_range.dart';
import '../model/object_embed_node.dart';

/// Super Editor twin of [DocumentMark]: marked span, else the caret line.
///
/// Object blocks stay as they are — chrome menus own those, not a text line.
DocumentSelection? caretLineSelection(
  Document document,
  DocumentSelection? selection,
) {
  if (selection == null) return null;
  final snapped = snapDocumentSelection(document, selection);
  if (!snapped.isCollapsed) return snapped;

  final node = document.getNodeById(snapped.extent.nodeId);
  if (node is ObjectEmbedNode) return snapped;
  if (node is! TextNode) return snapped;

  final plain = node.text.toPlainText();
  if (plain.isEmpty) return snapped;

  final offset = snapped.extent.nodePosition is TextNodePosition
      ? (snapped.extent.nodePosition as TextNodePosition).offset
      : 0;
  final range = LineRange.resolve(
    plain,
    TextSelection.collapsed(offset: offset.clamp(0, plain.length)),
  );
  if (!range.isValid) return snapped;

  return DocumentSelection(
    base: DocumentPosition(
      nodeId: node.id,
      nodePosition: TextNodePosition(offset: range.start),
    ),
    extent: DocumentPosition(
      nodeId: node.id,
      nodePosition: TextNodePosition(offset: range.end),
    ),
  );
}

/// Moves Super Editor caret / mark ends off the middle of a grapheme.
///
/// Emoji is two UTF-16 units. A mark that splits one throws
/// `string is not well-formed UTF-16` while Super Editor lays out.
DocumentSelection snapDocumentSelection(
  Document document,
  DocumentSelection selection,
) {
  if (selection.isCollapsed) {
    final next = _snapPosition(document, selection.extent, snapAsEnd: true);
    if (next == selection.extent) return selection;
    return DocumentSelection.collapsed(position: next);
  }

  final baseIndex = document.getNodeIndexById(selection.base.nodeId);
  final extentIndex = document.getNodeIndexById(selection.extent.nodeId);
  var baseIsStart = baseIndex < extentIndex;
  if (baseIndex == extentIndex &&
      selection.base.nodePosition is TextNodePosition &&
      selection.extent.nodePosition is TextNodePosition) {
    baseIsStart = (selection.base.nodePosition as TextNodePosition).offset <=
        (selection.extent.nodePosition as TextNodePosition).offset;
  } else if (baseIndex == extentIndex) {
    baseIsStart = true;
  }

  final newBase = _snapPosition(
    document,
    selection.base,
    snapAsEnd: !baseIsStart,
  );
  final newExtent = _snapPosition(
    document,
    selection.extent,
    snapAsEnd: baseIsStart,
  );
  if (newBase == selection.base && newExtent == selection.extent) {
    return selection;
  }
  return DocumentSelection(base: newBase, extent: newExtent);
}

DocumentPosition _snapPosition(
  Document document,
  DocumentPosition position, {
  required bool snapAsEnd,
}) {
  final node = document.getNodeById(position.nodeId);
  if (node is! TextNode) return position;
  if (position.nodePosition is! TextNodePosition) return position;
  final current = position.nodePosition as TextNodePosition;
  final plain = node.text.toPlainText();
  final snapped = snapAsEnd
      ? normalizeUtf16End(plain, current.offset)
      : normalizeUtf16Start(plain, current.offset);
  if (snapped == current.offset) return position;
  return DocumentPosition(
    nodeId: position.nodeId,
    nodePosition: TextNodePosition(offset: snapped, affinity: current.affinity),
  );
}
