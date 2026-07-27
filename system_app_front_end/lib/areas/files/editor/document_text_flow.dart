/// Makes the whole file behave like one continuous run of text.
///
/// The editor renders a separate text field per paragraph, per list bullet and
/// per table cell. Each of those is a **segment**. This flow puts the segments
/// in document order and owns the caret and selection *across* them, so arrow
/// keys walk out of one segment into the next and a selection can cover parts
/// of several.
///
/// Segment ids are built by [paragraphSegmentId], [listItemSegmentId] and
/// [tableCellSegmentId] so that order can be derived from the document tree
/// without the flow knowing anything about block types.
library;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

String paragraphSegmentId(String blockId) => blockId;

String listItemSegmentId(String blockId, int itemIndex) => '$blockId#i$itemIndex';

String tableCellSegmentId(String blockId, int row, int column) =>
    '$blockId#c$row:$column';

/// A caret position expressed against the document rather than one field.
@immutable
class DocumentTextPosition {
  const DocumentTextPosition(this.segmentId, this.offset);

  final String segmentId;
  final int offset;

  @override
  bool operator ==(Object other) =>
      other is DocumentTextPosition &&
      other.segmentId == segmentId &&
      other.offset == offset;

  @override
  int get hashCode => Object.hash(segmentId, offset);

  @override
  String toString() => 'DocumentTextPosition($segmentId, $offset)';
}

/// A selection that may start in one segment and end in another.
@immutable
class DocumentTextSelection {
  const DocumentTextSelection({required this.anchor, required this.focus});

  const DocumentTextSelection.collapsed(DocumentTextPosition at)
      : anchor = at,
        focus = at;

  /// Where the selection was started; stays put while the user extends.
  final DocumentTextPosition anchor;

  /// The moving end, where the caret is.
  final DocumentTextPosition focus;

  bool get isCollapsed => anchor == focus;

  bool get isWithinOneSegment => anchor.segmentId == focus.segmentId;

  @override
  bool operator ==(Object other) =>
      other is DocumentTextSelection &&
      other.anchor == anchor &&
      other.focus == focus;

  @override
  int get hashCode => Object.hash(anchor, focus);
}

/// The registered widget side of a segment.
class _SegmentBinding {
  _SegmentBinding(this.controller, this.focusNode, this.onChanged);

  final TextEditingController controller;
  final FocusNode focusNode;

  /// Pushes the controller's text back into the document model. Needed because
  /// programmatic edits do not go through `TextField.onChanged`.
  final VoidCallback? onChanged;
}

/// Ordered segments plus the document-wide caret and selection.
///
/// Order is pushed in by the editor via [setOrder] (it comes from the document
/// tree). Widgets attach themselves with [register]. The two are deliberately
/// separate: order must stay correct even for segments that are scrolled out of
/// the tree and therefore not registered.
class DocumentTextFlow extends ChangeNotifier {
  final _order = <String>[];
  final _bindings = <String, _SegmentBinding>{};
  // Vertical neighbours differ from reading order inside a table: pressing down
  // in a cell should reach the cell below it, not the next cell in the row.
  final _above = <String, String>{};
  final _below = <String, String>{};
  DocumentTextSelection? _selection;

  List<String> get order => List.unmodifiable(_order);

  DocumentTextSelection? get selection => _selection;

  /// True while a selection covers more than one segment — the case plain
  /// `TextField` selection cannot represent.
  bool get spansSegments {
    final current = _selection;
    return current != null &&
        !current.isCollapsed &&
        !current.isWithinOneSegment;
  }

  void setOrder(List<String> ids) {
    if (_listEquals(_order, ids)) return;
    _order
      ..clear()
      ..addAll(ids);
    final current = _selection;
    if (current != null &&
        (!_order.contains(current.anchor.segmentId) ||
            !_order.contains(current.focus.segmentId))) {
      _selection = null;
    }
    notifyListeners();
  }

  /// Overrides up/down targets for segments where reading order is not the
  /// visual order — currently table cells, which move by column.
  void setVerticalLinks({
    required Map<String, String> above,
    required Map<String, String> below,
  }) {
    if (_mapEquals(_above, above) && _mapEquals(_below, below)) return;
    _above
      ..clear()
      ..addAll(above);
    _below
      ..clear()
      ..addAll(below);
  }

  void register(
    String id,
    TextEditingController controller,
    FocusNode node, {
    VoidCallback? onChanged,
  }) {
    _bindings[id] = _SegmentBinding(controller, node, onChanged);
  }

  void unregister(String id, TextEditingController controller) {
    final existing = _bindings[id];
    if (existing == null || existing.controller != controller) return;
    _bindings.remove(id);
  }

  TextEditingController? controllerFor(String id) => _bindings[id]?.controller;

  FocusNode? focusNodeFor(String id) => _bindings[id]?.focusNode;

  VoidCallback? onChangedFor(String id) => _bindings[id]?.onChanged;

  /// The segment the caret is currently in, if any.
  String? get focusedSegmentId {
    final current = _selection;
    if (current != null) return current.focus.segmentId;
    for (final id in _order) {
      if (_bindings[id]?.focusNode.hasFocus ?? false) return id;
    }
    return null;
  }

  int indexOf(String id) => _order.indexOf(id);

  String? segmentBefore(String id) {
    final i = _order.indexOf(id);
    return i > 0 ? _order[i - 1] : null;
  }

  String? segmentAfter(String id) {
    final i = _order.indexOf(id);
    return i >= 0 && i < _order.length - 1 ? _order[i + 1] : null;
  }

  /// Length of a segment's text, or null when it is not currently attached.
  int? lengthOf(String id) => _bindings[id]?.controller.text.length;

  // ---------------------------------------------------------------- selection

  void collapseTo(DocumentTextPosition position) {
    _setSelection(DocumentTextSelection.collapsed(position));
  }

  /// Moves the focus end, keeping the anchor — this is shift+arrow / shift+click.
  void extendTo(DocumentTextPosition position) {
    final current = _selection;
    final anchor = current?.anchor ?? position;
    _setSelection(DocumentTextSelection(anchor: anchor, focus: position));
  }

  void clearSelection() => _setSelection(null);

  void _setSelection(DocumentTextSelection? next) {
    if (_selection == next) return;
    _selection = next;
    notifyListeners();
  }

  /// Orders the two ends by document position, so callers can treat the result
  /// as start→end regardless of which direction the user selected in.
  (DocumentTextPosition, DocumentTextPosition)? orderedSelection() {
    final current = _selection;
    if (current == null) return null;
    final anchorIndex = indexOf(current.anchor.segmentId);
    final focusIndex = indexOf(current.focus.segmentId);
    if (anchorIndex < 0 || focusIndex < 0) return null;
    if (anchorIndex < focusIndex) return (current.anchor, current.focus);
    if (focusIndex < anchorIndex) return (current.focus, current.anchor);
    return current.anchor.offset <= current.focus.offset
        ? (current.anchor, current.focus)
        : (current.focus, current.anchor);
  }

  /// The part of [id] that is selected, or null when the segment is untouched.
  ///
  /// Returns a full-width range for segments in the middle of a multi-segment
  /// selection, which is what lets the highlight look continuous.
  TextSelection? selectionWithin(String id) {
    final ends = orderedSelection();
    if (ends == null) return null;
    final (start, end) = ends;
    final index = indexOf(id);
    final startIndex = indexOf(start.segmentId);
    final endIndex = indexOf(end.segmentId);
    if (index < startIndex || index > endIndex) return null;

    final length = lengthOf(id);
    if (length == null) return null;

    final from = index == startIndex ? start.offset.clamp(0, length) : 0;
    final to = index == endIndex ? end.offset.clamp(0, length) : length;
    if (from == to) return null;
    return TextSelection(baseOffset: from, extentOffset: to);
  }

  /// Segment ids the selection touches, in document order.
  List<String> segmentsInSelection() {
    final ends = orderedSelection();
    if (ends == null) return const [];
    final (start, end) = ends;
    final startIndex = indexOf(start.segmentId);
    final endIndex = indexOf(end.segmentId);
    if (startIndex < 0 || endIndex < 0) return const [];
    return _order.sublist(startIndex, endIndex + 1);
  }

  /// Selected text with a newline between segments, matching what the user sees.
  String selectedText() {
    final parts = <String>[];
    for (final id in segmentsInSelection()) {
      final controller = _bindings[id]?.controller;
      final range = selectionWithin(id);
      if (controller == null || range == null) {
        parts.add('');
        continue;
      }
      final text = controller.text;
      parts.add(text.substring(
        range.start.clamp(0, text.length),
        range.end.clamp(0, text.length),
      ));
    }
    return parts.join('\n');
  }

  /// Selects everything in the document, from the first part to the last.
  void selectAll() {
    if (_order.isEmpty) return;
    final first = _order.first;
    final last = _order.last;
    collapseTo(DocumentTextPosition(first, 0));
    extendTo(DocumentTextPosition(last, lengthOf(last) ?? 0));
  }

  /// Set by the editor. Called after a delete with the parts that were emptied
  /// **entirely**, so the structures they belonged to can go too — a fully
  /// marked row, bullet, or table is removed rather than left blank.
  void Function(Set<String> fullyEmptied, {required bool spansParts})?
      onPruneStructures;

  /// Parts of the current selection that are covered end to end.
  Set<String> fullyMarkedSegments() {
    final result = <String>{};
    for (final id in segmentsInSelection()) {
      final range = selectionWithin(id);
      final length = lengthOf(id);
      if (range == null || length == null) continue;
      if (range.start == 0 && range.end == length && length > 0) result.add(id);
    }
    return result;
  }

  /// Removes the selected text from every part it touches, then asks the editor
  /// to drop any structure that was marked in full.
  ///
  /// Returns false when there was nothing to delete.
  bool deleteSelection() {
    if (!spansSegments) return false;
    final ends = orderedSelection();
    if (ends == null) return false;
    final (start, _) = ends;

    final touched = segmentsInSelection();
    final fullyEmptied = fullyMarkedSegments();
    var changed = false;

    for (final id in touched) {
      final binding = _bindings[id];
      final range = selectionWithin(id);
      if (binding == null || range == null) continue;

      final text = binding.controller.text;
      final from = range.start.clamp(0, text.length);
      final to = range.end.clamp(0, text.length);
      if (from == to) continue;

      binding.controller.value = binding.controller.value.copyWith(
        text: text.replaceRange(from, to, ''),
        selection: TextSelection.collapsed(offset: from),
        composing: TextRange.empty,
      );
      binding.onChanged?.call();
      changed = true;
    }

    if (!changed) return false;
    placeCaret(start);
    pruneStructures(fullyEmptied, spansParts: touched.length > 1);
    return true;
  }

  void pruneStructures(Set<String> fullyEmptied, {required bool spansParts}) {
    if (fullyEmptied.isEmpty) return;
    onPruneStructures?.call(fullyEmptied, spansParts: spansParts);
  }

  /// Inserts [text] at [position], used to replace a multi-part selection with
  /// whatever the user typed.
  void insertTextAt(DocumentTextPosition position, String text) {
    if (text.isEmpty) return;
    final binding = _bindings[position.segmentId];
    if (binding == null) return;

    final current = binding.controller.text;
    final at = position.offset.clamp(0, current.length);
    binding.controller.value = binding.controller.value.copyWith(
      text: current.replaceRange(at, at, text),
      selection: TextSelection.collapsed(offset: at + text.length),
      composing: TextRange.empty,
    );
    binding.onChanged?.call();
    collapseTo(DocumentTextPosition(position.segmentId, at + text.length));
  }

  /// The caret position under a screen point, used for dragging a selection
  /// across parts.
  ///
  /// A point in the gaps between parts resolves to the vertically nearest one,
  /// so dragging past the end of the document keeps extending instead of
  /// stalling.
  DocumentTextPosition? positionAtGlobal(Offset globalPosition) {
    String? bestId;
    RenderBox? bestBox;
    var bestDistance = double.infinity;

    for (final id in _order) {
      final context = _bindings[id]?.focusNode.context;
      final box = context?.findRenderObject();
      if (box is! RenderBox || !box.hasSize || !box.attached) continue;

      final rect = box.localToGlobal(Offset.zero) & box.size;
      final distance = globalPosition.dy < rect.top
          ? rect.top - globalPosition.dy
          : globalPosition.dy > rect.bottom
              ? globalPosition.dy - rect.bottom
              : 0.0;
      // Prefer a direct hit; otherwise keep the closest by vertical distance.
      if (distance == 0 && rect.contains(globalPosition)) {
        bestId = id;
        bestBox = box;
        break;
      }
      if (distance < bestDistance) {
        bestDistance = distance;
        bestId = id;
        bestBox = box;
      }
    }

    if (bestId == null || bestBox == null) return null;
    final editable = _findRenderEditable(bestBox);
    if (editable == null) return DocumentTextPosition(bestId, 0);
    return DocumentTextPosition(
      bestId,
      editable.getPositionForPoint(globalPosition).offset,
    );
  }

  // --------------------------------------------------------------- navigation

  /// Caret target one step before [position], crossing into the previous
  /// segment when already at the start of this one. Null at the document start.
  DocumentTextPosition? positionBefore(DocumentTextPosition position) {
    if (position.offset > 0) {
      return DocumentTextPosition(position.segmentId, position.offset - 1);
    }
    final previous = segmentBefore(position.segmentId);
    if (previous == null) return null;
    return DocumentTextPosition(previous, lengthOf(previous) ?? 0);
  }

  /// Caret target one step after [position], crossing into the next segment
  /// when already at the end of this one. Null at the document end.
  DocumentTextPosition? positionAfter(DocumentTextPosition position) {
    final length = lengthOf(position.segmentId);
    if (length != null && position.offset < length) {
      return DocumentTextPosition(position.segmentId, position.offset + 1);
    }
    final next = segmentAfter(position.segmentId);
    if (next == null) return null;
    return DocumentTextPosition(next, 0);
  }

  /// Target when moving up out of a segment.
  ///
  /// Lands on the target's **last** line — it is the line directly above the
  /// caret — at the same horizontal position, which is what makes a bullet or
  /// a row behave like just another line of the text.
  DocumentTextPosition? positionAbove(
    DocumentTextPosition position, {
    int? preferredOffset,
    double? caretX,
  }) {
    final previous = _above[position.segmentId] ?? segmentBefore(position.segmentId);
    if (previous == null) return null;
    return DocumentTextPosition(
      previous,
      _offsetOnEdgeLine(previous, caretX: caretX, preferredOffset: preferredOffset, last: true),
    );
  }

  /// Target when moving down out of a segment, landing on the target's first
  /// line at the same horizontal position.
  DocumentTextPosition? positionBelow(
    DocumentTextPosition position, {
    int? preferredOffset,
    double? caretX,
  }) {
    final next = _below[position.segmentId] ?? segmentAfter(position.segmentId);
    if (next == null) return null;
    return DocumentTextPosition(
      next,
      _offsetOnEdgeLine(next, caretX: caretX, preferredOffset: preferredOffset, last: false),
    );
  }

  /// Offset on the first or last line of [id], at [caretX] when the segment is
  /// laid out, otherwise approximated from [preferredOffset] as a column.
  int _offsetOnEdgeLine(
    String id, {
    required double? caretX,
    required int? preferredOffset,
    required bool last,
  }) {
    final text = _bindings[id]?.controller.text ?? '';
    final length = text.length;

    final editable = _editableFor(id);
    if (editable != null && caretX != null) {
      final anchor = editable.getLocalRectForCaret(
        TextPosition(offset: last ? length : 0),
      );
      final y = editable.localToGlobal(anchor.center).dy;
      return editable.getPositionForPoint(Offset(caretX, y)).offset;
    }

    if (preferredOffset == null) return last ? length : 0;
    // Without layout, treat a hard line break as the line boundary.
    final lineStart = last ? text.lastIndexOf('\n') + 1 : 0;
    final lineEnd = last ? length : _firstLineEnd(text);
    return (lineStart + preferredOffset).clamp(lineStart, lineEnd);
  }

  static int _firstLineEnd(String text) {
    final index = text.indexOf('\n');
    return index == -1 ? text.length : index;
  }

  RenderEditable? _editableFor(String id) {
    final context = _bindings[id]?.focusNode.context;
    final object = context?.findRenderObject();
    if (object == null || !object.attached) return null;
    return _findRenderEditable(object);
  }

  /// Puts the caret in [position]'s segment, focusing it if it is attached.
  void placeCaret(DocumentTextPosition position, {bool extendSelection = false}) {
    if (extendSelection) {
      extendTo(position);
    } else {
      collapseTo(position);
    }

    final binding = _bindings[position.segmentId];
    if (binding == null) return;
    final length = binding.controller.text.length;
    final offset = position.offset.clamp(0, length);

    if (!binding.focusNode.hasFocus && binding.focusNode.canRequestFocus) {
      binding.focusNode.requestFocus();
    }
    binding.controller.selection = TextSelection.collapsed(offset: offset);
  }

  @override
  void dispose() {
    _bindings.clear();
    _order.clear();
    super.dispose();
  }
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

RenderEditable? _findRenderEditable(RenderObject root) {
  if (root is RenderEditable) return root;
  RenderEditable? found;
  root.visitChildren((child) {
    found ??= _findRenderEditable(child);
  });
  return found;
}

bool _mapEquals(Map<String, String> a, Map<String, String> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}

/// Exposes the flow to the text fields nested under the editor.
class DocumentTextFlowScope extends InheritedNotifier<DocumentTextFlow> {
  const DocumentTextFlowScope({
    super.key,
    required DocumentTextFlow flow,
    required super.child,
  }) : super(notifier: flow);

  static DocumentTextFlow? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<DocumentTextFlowScope>()
        ?.notifier;
  }

  /// Reads the flow without subscribing — for key handlers and callbacks that
  /// must not cause a rebuild on every caret move.
  static DocumentTextFlow? readOf(BuildContext context) {
    return context
        .getInheritedWidgetOfExactType<DocumentTextFlowScope>()
        ?.notifier;
  }
}
