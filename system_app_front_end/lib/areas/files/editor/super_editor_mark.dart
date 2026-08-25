import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

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
  if (!selection.isCollapsed) return selection;

  final node = document.getNodeById(selection.extent.nodeId);
  if (node is ObjectEmbedNode) return selection;
  if (node is! TextNode) return selection;

  final plain = node.text.toPlainText();
  if (plain.isEmpty) return selection;

  final offset = selection.extent.nodePosition is TextNodePosition
      ? (selection.extent.nodePosition as TextNodePosition).offset
      : 0;
  final range = LineRange.resolve(
    plain,
    TextSelection.collapsed(offset: offset.clamp(0, plain.length)),
  );
  if (!range.isValid) return selection;

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
