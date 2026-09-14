import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';

/// Logical range endpoints from the selected boundary graphemes. Whole-range
/// boxes can be in visual run order, which puts iOS handles beside the numbers
/// instead of at the start/end of the selected Hebrew text.
List<Offset>? editableLogicalSelectionEndpoints(
  RenderEditable editable,
  String text,
  TextSelection selection,
) {
  if (!selection.isValid ||
      selection.isCollapsed ||
      selection.end > text.length)
    return null;
  final firstEnd =
      selection.start + text.substring(selection.start).characters.first.length;
  final lastStart =
      selection.end - text.substring(0, selection.end).characters.last.length;
  final first = editable.getBoxesForSelection(
    TextSelection(baseOffset: selection.start, extentOffset: firstEnd),
  );
  final last = editable.getBoxesForSelection(
    TextSelection(baseOffset: lastStart, extentOffset: selection.end),
  );
  if (first.isEmpty || last.isEmpty) return null;
  return [
    Offset(first.first.start, first.first.bottom),
    Offset(last.last.end, last.last.bottom),
  ];
}

class ObjectCupertinoSelectionControls extends CupertinoTextSelectionControls
    with TextSelectionHandleControls {
  ObjectCupertinoSelectionControls(this.editable, this.text);
  final RenderEditable? Function() editable;
  final String Function() text;

  @override
  Offset getHandleAnchor(TextSelectionHandleType type, double textLineHeight) {
    final anchor = super.getHandleAnchor(type, textLineHeight);
    if (type == TextSelectionHandleType.collapsed) return anchor;
    final render = editable();
    final selection = render?.selection;
    if (render == null || selection == null || selection.isCollapsed)
      return anchor;
    final logical = editableLogicalSelectionEndpoints(
      render,
      text(),
      selection,
    );
    final native = render.getEndpointsForSelection(selection);
    if (logical == null || native.length != 2) return anchor;
    final start = render.textDirection == TextDirection.rtl
        ? type == TextSelectionHandleType.right
        : type == TextSelectionHandleType.left;
    final index = start ? 0 : 1;
    return anchor + native[index].point - logical[index];
  }
}
