/// Makes the fields **inside one object** behave like one continuous run of text.
///
/// The file body is Super Editor. Each open object (a task list, a table) owns
/// its own flow so Shift+arrows and Shift+click can mark several tasks or cells
/// in that object. Flows do not cross objects or into the file body.
///
/// Each inner field is a **segment**. This flow puts the segments in visual
/// order and owns the caret and selection *across* them.
///
/// Segment ids are built by [paragraphSegmentId], [listItemSegmentId],
/// [tableCellSegmentId], [taskItemSegmentId] and [embedSegmentId] so that order
/// can be derived without the flow knowing anything about block types.
library;

import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

String paragraphSegmentId(String blockId) => blockId;

String listItemSegmentId(String blockId, int itemIndex) =>
    '$blockId#i$itemIndex';

String tableCellSegmentId(String blockId, int row, int column) =>
    '$blockId#c$row:$column';

(String blockId, int row, int column)? parseTableCellSegmentId(
  String segmentId,
) {
  final match = RegExp(r'^(.*)#c(\d+):(\d+)$').firstMatch(segmentId);
  if (match == null) return null;
  return (
    match.group(1)!,
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  );
}

/// One task title inside a task-list embed — same role as a list bullet.
String taskItemSegmentId(String blockId, int itemIndex) =>
    '$blockId#t$itemIndex';

/// One graph cell — same role as a table cell (`row` is 0=label, 1=value).
String graphCellSegmentId(String blockId, int row, int column) =>
    '$blockId#g$row:$column';

/// One whole embedded object — atomic for caret and marking (info / image).
String embedSegmentId(String blockId) => '$blockId#embed';

bool isEmbedSegmentId(String segmentId) => segmentId.endsWith('#embed');

/// Info object — one editable text field (first line = title for API/diagrams).
String infoTextSegmentId(String blockId) => '$blockId#infoText';

/// Legacy: separate title field (pre first-line-title model).
String infoTitleSegmentId(String blockId) => '$blockId#infoTitle';

/// Legacy: separate body field (pre first-line-title model).
String infoBodySegmentId(String blockId) => '$blockId#infoBody';

/// Task list object header — one line above the task rows.
String taskListTitleSegmentId(String blockId) => '$blockId#taskListTitle';

bool isTaskItemSegmentId(String segmentId) =>
    RegExp(r'#t\d+$').hasMatch(segmentId);

bool isGraphCellSegmentId(String segmentId) =>
    RegExp(r'#g\d+:\d+$').hasMatch(segmentId);

(String blockId, int index)? parseTaskItemSegmentId(String segmentId) {
  final match = RegExp(r'^(.*)#t(\d+)$').firstMatch(segmentId);
  if (match == null) return null;
  return (match.group(1)!, int.parse(match.group(2)!));
}

(String blockId, int row, int column)? parseGraphCellSegmentId(
  String segmentId,
) {
  final match = RegExp(r'^(.*)#g(\d+):(\d+)$').firstMatch(segmentId);
  if (match == null) return null;
  return (
    match.group(1)!,
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  );
}

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

  /// Absolute start offset of each segment in the marker-text buffer.
  final _baseOffset = <String, int>{};
  // Grid neighbours differ from reading order inside a table: down stays in
  // the column, left/right stay in the row (visual, via TableGridNav).
  final _above = <String, String>{};
  final _below = <String, String>{};
  final _left = <String, String>{};
  final _right = <String, String>{};
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

  /// Overrides left/right targets for table cells (visual neighbours).
  void setHorizontalLinks({
    required Map<String, String> left,
    required Map<String, String> right,
  }) {
    if (_mapEquals(_left, left) && _mapEquals(_right, right)) return;
    _left
      ..clear()
      ..addAll(left);
    _right
      ..clear()
      ..addAll(right);
  }

  /// Visual neighbour of a table cell, if this flow has grid links.
  String? gridNeighbor(String id, AxisDirection direction) {
    return switch (direction) {
      AxisDirection.left => _left[id],
      AxisDirection.right => _right[id],
      AxisDirection.up => _above[id],
      AxisDirection.down => _below[id],
    };
  }

  bool hasGridNeighbors(String id) =>
      _left.containsKey(id) ||
      _right.containsKey(id) ||
      _above.containsKey(id) ||
      _below.containsKey(id);

  void register(
    String id,
    TextEditingController controller,
    FocusNode node, {
    VoidCallback? onChanged,
    int baseOffset = 0,
  }) {
    _bindings[id] = _SegmentBinding(controller, node, onChanged);
    _baseOffset[id] = baseOffset;
  }

  void unregister(String id, TextEditingController controller) {
    final existing = _bindings[id];
    if (existing == null || existing.controller != controller) return;
    _bindings.remove(id);
    _baseOffset.remove(id);
  }

  /// Drop all field bindings (call when controllers are disposed for rebuild).
  void clearBindings() {
    _bindings.clear();
    _baseOffset.clear();
  }

  /// Start of [id] in the document buffer, if registered.
  int baseOffsetOf(String id) => _baseOffset[id] ?? 0;

  /// Global caret offset = part base + local offset.
  int? globalOffsetOf(DocumentTextPosition position) {
    if (!_order.contains(position.segmentId)) return null;
    return baseOffsetOf(position.segmentId) + position.offset;
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
  /// Table / task marks that span several fields cover each field end to end
  /// (a cell is a unit). A 1D mark inside prose still uses the real offsets.
  TextSelection? selectionWithin(String id) {
    final covered = segmentsInSelection();
    if (!covered.contains(id)) return null;
    final length = lengthOf(id);
    if (length == null) return null;

    if (_markUsesWholeFields) {
      if (length == 0) return null;
      return TextSelection(baseOffset: 0, extentOffset: length);
    }

    final ends = orderedSelection();
    if (ends == null) return null;
    final (start, end) = ends;
    final index = indexOf(id);
    final startIndex = indexOf(start.segmentId);
    final endIndex = indexOf(end.segmentId);
    if (index < 0 || startIndex < 0 || endIndex < 0) return null;

    final from = index == startIndex ? start.offset.clamp(0, length) : 0;
    final to = index == endIndex ? end.offset.clamp(0, length) : length;
    if (from == to) return null;
    return TextSelection(baseOffset: from, extentOffset: to);
  }

  /// Segment ids the selection touches, in document order.
  ///
  /// Table marks are the bounding rectangle of the two cells, not the
  /// reading-order slice between them (which would include extra cells).
  List<String> segmentsInSelection() {
    final current = _selection;
    if (current == null) return const [];
    final rect = _tableRectIds(current);
    if (rect != null) return rect;
    final ends = orderedSelection();
    if (ends == null) return const [];
    final (start, end) = ends;
    final startIndex = indexOf(start.segmentId);
    final endIndex = indexOf(end.segmentId);
    if (startIndex < 0 || endIndex < 0) return const [];
    return _order.sublist(startIndex, endIndex + 1);
  }

  bool get _markUsesWholeFields {
    final current = _selection;
    if (current == null || current.isWithinOneSegment) return false;
    if (_tableRectIds(current) != null) return true;
    return parseTaskItemSegmentId(current.anchor.segmentId) != null &&
        parseTaskItemSegmentId(current.focus.segmentId) != null;
  }

  List<String>? _tableRectIds(DocumentTextSelection sel) {
    if (sel.isWithinOneSegment) return null;
    final a = parseTableCellSegmentId(sel.anchor.segmentId);
    final b = parseTableCellSegmentId(sel.focus.segmentId);
    if (a == null || b == null || a.$1 != b.$1) return null;
    final r0 = math.min(a.$2, b.$2);
    final r1 = math.max(a.$2, b.$2);
    final c0 = math.min(a.$3, b.$3);
    final c1 = math.max(a.$3, b.$3);
    return [
      for (final id in _order)
        if (_cellInRect(id, a.$1, r0, r1, c0, c1)) id,
    ];
  }

  bool _cellInRect(String id, String blockId, int r0, int r1, int c0, int c1) {
    final parsed = parseTableCellSegmentId(id);
    if (parsed == null || parsed.$1 != blockId) return false;
    return parsed.$2 >= r0 &&
        parsed.$2 <= r1 &&
        parsed.$3 >= c0 &&
        parsed.$3 <= c1;
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
      parts.add(
        text.substring(
          range.start.clamp(0, text.length),
          range.end.clamp(0, text.length),
        ),
      );
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

  /// True when [globalPosition] lies inside a registered segment's box.
  bool segmentContainsGlobal(Offset globalPosition) {
    for (final id in _order) {
      final context = _bindings[id]?.focusNode.context;
      final box = context?.findRenderObject();
      if (box is! RenderBox || !box.hasSize || !box.attached) continue;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      if (rect.contains(globalPosition)) return true;
    }
    return false;
  }

  /// The caret position under a screen point, used for dragging a selection
  /// across parts and for taps in empty space **outside** every field.
  ///
  /// Inside a field box: Flutter hit-test only. In-field empty-padding / RTL
  /// policy lives in [`rich_text/rtl/`](../rich_text/rtl/RTL.md). Under-file
  /// empty space is structure: logical end of the last part above.
  DocumentTextPosition? positionAtGlobal(Offset globalPosition) {
    String? hitId;
    RenderBox? hitBox;
    final tops = <String, double>{};
    final bottoms = <String, double>{};

    for (final id in _order) {
      final context = _bindings[id]?.focusNode.context;
      final box = context?.findRenderObject();
      if (box is! RenderBox || !box.hasSize || !box.attached) continue;

      final rect = box.localToGlobal(Offset.zero) & box.size;
      tops[id] = rect.top;
      bottoms[id] = rect.bottom;
      if (rect.contains(globalPosition)) {
        hitId = id;
        hitBox = box;
        break;
      }
    }

    if (hitId != null && hitBox != null) {
      final editable = _findRenderEditable(hitBox);
      final length = lengthOf(hitId) ?? 0;
      if (editable == null) {
        return DocumentTextPosition(hitId, length);
      }
      return DocumentTextPosition(
        hitId,
        editable.getPositionForPoint(globalPosition).offset,
      );
    }

    return resolvePointerMiss(
      order: _order,
      tops: tops,
      bottoms: bottoms,
      dy: globalPosition.dy,
      lengthOf: (id) => lengthOf(id) ?? 0,
    );
  }

  /// Pure miss resolution for empty space below / above / between segments.
  ///
  /// Exposed for tests; [positionAtGlobal] uses this when the point is not
  /// inside or beside any segment box.
  @visibleForTesting
  static DocumentTextPosition? resolvePointerMiss({
    required List<String> order,
    required Map<String, double> tops,
    required Map<String, double> bottoms,
    required double dy,
    required int Function(String id) lengthOf,
  }) {
    String? lastAboveId;
    var lastAboveBottom = double.negativeInfinity;
    String? firstBelowId;
    var firstBelowTop = double.infinity;

    for (final id in order) {
      final top = tops[id];
      final bottom = bottoms[id];
      if (top == null || bottom == null) continue;
      if (bottom <= dy && bottom >= lastAboveBottom) {
        lastAboveBottom = bottom;
        lastAboveId = id;
      }
      if (top >= dy && top < firstBelowTop) {
        firstBelowTop = top;
        firstBelowId = id;
      }
    }

    if (lastAboveId != null) {
      return DocumentTextPosition(lastAboveId, lengthOf(lastAboveId));
    }
    if (firstBelowId != null) {
      return DocumentTextPosition(firstBelowId, 0);
    }
    if (order.isEmpty) return null;
    final last = order.last;
    return DocumentTextPosition(last, lengthOf(last));
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
    final previous =
        _above[position.segmentId] ?? segmentBefore(position.segmentId);
    if (previous == null) return null;
    return DocumentTextPosition(
      previous,
      _offsetOnEdgeLine(
        previous,
        caretX: caretX,
        preferredOffset: preferredOffset,
        last: true,
      ),
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
      _offsetOnEdgeLine(
        next,
        caretX: caretX,
        preferredOffset: preferredOffset,
        last: false,
      ),
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
  ///
  /// End-of-text placements use [TextAffinity.upstream] so soft-wrap / BiDi
  /// boundaries prefer the end of the line over the start of the next run.
  void placeCaret(
    DocumentTextPosition position, {
    bool extendSelection = false,
  }) {
    if (extendSelection) {
      extendTo(position);
    } else {
      collapseTo(position);
    }

    final binding = _bindings[position.segmentId];
    if (binding == null) return;
    // Rebuild can leave a stale binding whose controller was already disposed.
    if (binding.focusNode.context == null) return;
    final length = binding.controller.text.length;
    final offset = position.offset.clamp(0, length);

    if (!binding.focusNode.hasFocus && binding.focusNode.canRequestFocus) {
      binding.focusNode.requestFocus();
    }
    binding.controller.selection = TextSelection.collapsed(
      offset: offset,
      affinity: offset >= length
          ? TextAffinity.upstream
          : TextAffinity.downstream,
    );
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
