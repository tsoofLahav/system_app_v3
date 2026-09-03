import 'dart:ui' show BoxWidthStyle;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:super_editor/super_editor.dart';

/// iOS expanded-handle geometry: Super Editor identity, tight wash snap.
///
/// Upstream (top ball) is [Document.selectUpstreamPosition]; downstream
/// (bottom ball) is [Document.selectDownstreamPosition]. X/Y come from tight
/// [TextComponentState.textLayout.getBoxesForSelection] boxes, snapped to the
/// edge nearest that document position so Hebrew stems sit on the glyphs —
/// not a full-line `max` box, and not visual-left = upstream. Fallback is
/// Super Editor’s one-character expand.
DocumentSelectionLayout? visualIosExpandedHandleLayout({
  required Document document,
  required DocumentLayout documentLayout,
  required DocumentSelection selection,
}) {
  if (selection.isCollapsed) return null;

  final upstreamPos = document.selectUpstreamPosition(
    selection.base,
    selection.extent,
  );
  final downstreamPos = document.selectDownstreamPosition(
    selection.base,
    selection.extent,
  );

  final upstream =
      tightHandleRectForPosition(
        documentLayout: documentLayout,
        selection: selection,
        position: upstreamPos,
      ) ??
      computeRectForExpandedHandle(documentLayout, upstreamPos);
  final downstream =
      tightHandleRectForPosition(
        documentLayout: documentLayout,
        selection: selection,
        position: downstreamPos,
      ) ??
      computeRectForExpandedHandle(documentLayout, downstreamPos);

  if (upstream == null || downstream == null) return null;

  return DocumentSelectionLayout(
    upstream: upstream,
    downstream: downstream,
    expandedSelectionBounds: documentLayout.getRectForSelection(
      selection.base,
      selection.extent,
    ),
  );
}

/// Zero-width stem on the tight wash edge nearest [position].
Rect? tightHandleRectForPosition({
  required DocumentLayout documentLayout,
  required DocumentSelection selection,
  required DocumentPosition position,
}) {
  final component = _textComponentOf(
    documentLayout.getComponentByNodeId(position.nodeId),
  );
  if (component == null) return null;
  if (position.nodePosition is! TextNodePosition) return null;

  final nodeSelection = _textSelectionInNode(selection, position.nodeId);
  if (nodeSelection == null || nodeSelection.isCollapsed) return null;

  final List<TextBox> boxes;
  try {
    // Super Editor marks [TextComponentState.textLayout] @visibleForTesting.
    // ignore: invalid_use_of_visible_for_testing_member
    boxes = component.textLayout.getBoxesForSelection(
      nodeSelection,
      boxWidthStyle: BoxWidthStyle.tight,
    );
  } catch (_) {
    return null;
  }
  if (boxes.isEmpty) return null;

  final renderObject = component.context.findRenderObject();
  if (renderObject is! RenderBox) return null;

  final docOrigin = documentLayout.getDocumentOffsetFromAncestorOffset(
    renderObject.localToGlobal(Offset.zero),
  );
  final docBoxes = [
    for (final box in boxes)
      Rect.fromLTRB(box.left, box.top, box.right, box.bottom).shift(docOrigin),
  ];

  final caret = documentLayout.getRectForPosition(position);
  final probe = caret ?? docBoxes.first;
  final onLine = [
    for (final box in docBoxes)
      if (_verticalGap(box, probe) == 0) box,
  ];
  final wash = onLine.isEmpty
      ? _boxNearestPosition(docBoxes, probe)
      : _union(onLine);
  final snapLeft =
      (probe.left - wash.left).abs() <= (probe.left - wash.right).abs();
  return Rect.fromLTWH(
    snapLeft ? wash.left : wash.right,
    wash.top,
    0,
    wash.height,
  );
}

Rect _union(List<Rect> boxes) {
  var result = boxes.first;
  for (var i = 1; i < boxes.length; i++) {
    result = result.expandToInclude(boxes[i]);
  }
  return result;
}

/// Super Editor’s one-character expand when tight boxes are missing.
Rect? computeRectForExpandedHandle(
  DocumentLayout documentLayout,
  DocumentPosition position,
) {
  final component = documentLayout.getComponentByNodeId(position.nodeId);
  if (component == null) return null;

  var extentNodePosition = component.movePositionRight(position.nodePosition);
  var isExtentDownstream = extentNodePosition != null;
  extentNodePosition ??= component.movePositionLeft(position.nodePosition);

  if (extentNodePosition == null) {
    return documentLayout.getRectForPosition(position);
  }

  final rectForSelection = documentLayout.getRectForSelection(
    position,
    DocumentPosition(
      nodeId: position.nodeId,
      nodePosition: extentNodePosition,
    ),
  );
  if (rectForSelection == null) {
    return documentLayout.getRectForPosition(position);
  }

  return Rect.fromLTWH(
    isExtentDownstream ? rectForSelection.left : rectForSelection.right,
    rectForSelection.top,
    0,
    rectForSelection.height,
  );
}

TextSelection? _textSelectionInNode(
  DocumentSelection selection,
  String nodeId,
) {
  final base = selection.base;
  final extent = selection.extent;
  if (base.nodeId != nodeId || extent.nodeId != nodeId) return null;
  final basePos = base.nodePosition;
  final extentPos = extent.nodePosition;
  if (basePos is! TextNodePosition || extentPos is! TextNodePosition) {
    return null;
  }
  return TextSelection(
    baseOffset: basePos.offset,
    extentOffset: extentPos.offset,
  );
}

Rect _boxNearestPosition(List<Rect> boxes, Rect probe) {
  var best = boxes.first;
  var bestScore = double.infinity;
  for (final box in boxes) {
    final dy = _verticalGap(box, probe);
    final dx = (probe.left - box.center.dx).abs();
    final score = dy * 1000 + dx;
    if (score < bestScore) {
      bestScore = score;
      best = box;
    }
  }
  return best;
}

TextComponentState? _textComponentOf(DocumentComponent? component) {
  if (component == null) return null;
  if (component is TextComponentState) return component;
  TextComponentState? found;
  void visit(Element el) {
    if (found != null) return;
    if (el is StatefulElement && el.state is TextComponentState) {
      found = el.state as TextComponentState;
      return;
    }
    el.visitChildren(visit);
  }

  final ctx = component.context;
  if (ctx is Element) ctx.visitChildren(visit);
  return found;
}

double _verticalGap(Rect a, Rect b) {
  if (a.bottom < b.top) return b.top - a.bottom;
  if (b.bottom < a.top) return a.top - b.bottom;
  return 0;
}
