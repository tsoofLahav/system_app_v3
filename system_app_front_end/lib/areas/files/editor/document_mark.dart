/// The **mark** — the single thing every text action operates on.
///
/// There is exactly one notion of "what the user means right now", shared by
/// the right-click menu, clipboard actions, formatting and AI actions. It is
/// resolved once by [DocumentMark.resolve] using one rule:
///
/// 1. If anything is marked, the mark is that selection — even when it runs
///    across several paragraphs, bullets or table cells.
/// 2. If nothing is marked, the mark is the **line at the caret**.
///
/// Paste is the exception: unmarked paste inserts at the caret
/// ([fromMarking] is false). Copy, cut, format, and AI still use the caret
/// line. Super Editor body paste already skips caret-line expansion.
///
/// Nothing else may look at a single field's selection to decide what to act
/// on, or the two would drift apart and actions would hit the wrong text.
library;

import 'package:flutter/material.dart';

import '../model/line_range.dart';
import '../rich_text/format_range.dart';
import '../rich_text/span_text_editing_controller.dart';
import './document_text_flow.dart';

/// One part's share of the mark.
@immutable
class MarkedSpan {
  const MarkedSpan({
    required this.controller,
    required this.start,
    required this.end,
    this.segmentId,
    this.onChanged,
  });

  final TextEditingController controller;
  final int start;
  final int end;

  /// Null when the field is not part of a document flow (e.g. a task title).
  final String? segmentId;

  /// Pushes the controller's text back into the document model.
  final VoidCallback? onChanged;

  bool get isEmpty => end <= start;

  int get _length => controller.text.length;

  int get safeStart => start.clamp(0, _length);

  int get safeEnd => end.clamp(0, _length);

  String get text {
    final from = safeStart;
    final to = safeEnd;
    return to <= from ? '' : controller.text.substring(from, to);
  }

  SpanTextEditingController? get spanController {
    final c = controller;
    return c is SpanTextEditingController ? c : null;
  }

  TextSelection get selection =>
      TextSelection(baseOffset: safeStart, extentOffset: safeEnd);
}

/// A resolved target for an action: one or more parts, in document order.
@immutable
class DocumentMark {
  const DocumentMark(this.spans, {this.fromMarking = false});

  const DocumentMark.empty() : spans = const [], fromMarking = false;

  final List<MarkedSpan> spans;

  /// True when the user marked text. False for the caret-line fallback.
  /// Paste replaces only when this is true; otherwise it inserts at the caret.
  final bool fromMarking;

  bool get isEmpty => spans.isEmpty || spans.every((s) => s.isEmpty);

  bool get isValid => !isEmpty;

  /// True when the mark covers more than one part, which no single text field
  /// can represent on its own.
  bool get spansParts => spans.length > 1;

  /// The marked text, parts joined by newlines the way the user sees them.
  String get text => spans.map((s) => s.text).join('\n');

  MarkedSpan? get first => spans.isEmpty ? null : spans.first;

  /// Parts the mark covers end to end. Read this **before** deleting — the
  /// editor uses it to drop the row, bullet, or table that was fully marked.
  Set<String> get fullyCoveredSegmentIds => {
    for (final span in spans)
      if (span.segmentId != null &&
          span.safeStart == 0 &&
          span.safeEnd == span.controller.text.length)
        span.segmentId!,
  };

  // ---------------------------------------------------------------- resolving

  /// Resolves the mark for a document flow.
  ///
  /// Applies the single rule: the selection when there is one, otherwise the
  /// line at the caret.
  static DocumentMark resolve(DocumentTextFlow flow) {
    final selection = flow.selection;

    if (selection != null && !selection.isCollapsed) {
      final spans = <MarkedSpan>[];
      for (final id in flow.segmentsInSelection()) {
        final controller = flow.controllerFor(id);
        final range = flow.selectionWithin(id);
        if (controller == null) continue;
        if (range == null) {
          if (controller.text.isEmpty) {
            spans.add(
              MarkedSpan(
                segmentId: id,
                controller: controller,
                start: 0,
                end: 0,
                onChanged: flow.onChangedFor(id),
              ),
            );
          }
          continue;
        }
        spans.add(
          MarkedSpan(
            segmentId: id,
            controller: controller,
            start: range.start,
            end: range.end,
            onChanged: flow.onChangedFor(id),
          ),
        );
      }
      if (spans.isNotEmpty) {
        return DocumentMark(spans, fromMarking: true);
      }
    }

    // Nothing marked: fall back to the line holding the caret.
    final segmentId = flow.focusedSegmentId;
    if (segmentId == null) return const DocumentMark.empty();
    final controller = flow.controllerFor(segmentId);
    if (controller == null) return const DocumentMark.empty();

    final caret = selection?.focus.segmentId == segmentId
        ? TextSelection.collapsed(offset: selection!.focus.offset)
        : controller.selection;
    final line = LineRange.resolve(controller.text, caret);
    return DocumentMark([
      MarkedSpan(
        segmentId: segmentId,
        controller: controller,
        start: line.start,
        end: line.end,
        onChanged: flow.onChangedFor(segmentId),
      ),
    ]);
  }

  /// Resolves the mark for a lone text field with no document flow around it.
  static DocumentMark resolveForController(
    TextEditingController controller, {
    VoidCallback? onChanged,
  }) {
    final selection = controller.selection;
    final line = LineRange.resolve(controller.text, selection);
    return DocumentMark([
      MarkedSpan(
        controller: controller,
        start: line.start,
        end: line.end,
        onChanged: onChanged,
      ),
    ], fromMarking: selection.isValid && !selection.isCollapsed);
  }

  // --------------------------------------------------------------- operations

  /// Clears the marked text from every part it covers.
  ///
  /// Text only: a part that ends up empty is kept, so no bullet, row or block
  /// vanishes as a side effect of an edit.
  bool delete() {
    var changed = false;
    for (final span in spans) {
      if (span.isEmpty) continue;
      final text = span.controller.text;
      span.controller.value = span.controller.value.copyWith(
        text: text.replaceRange(span.safeStart, span.safeEnd, ''),
        selection: TextSelection.collapsed(offset: span.safeStart),
        composing: TextRange.empty,
      );
      span.spanController?.ensureSpansMatchText();
      span.onChanged?.call();
      changed = true;
    }
    return changed;
  }

  /// Replaces everything marked with [replacement], which lands in the first
  /// part.
  bool replaceWith(String replacement) {
    final target = first;
    if (target == null) return false;
    final at = target.safeStart;

    delete();

    if (replacement.isNotEmpty) {
      final text = target.controller.text;
      final index = at.clamp(0, text.length);
      target.controller.value = target.controller.value.copyWith(
        text: text.replaceRange(index, index, replacement),
        selection: TextSelection.collapsed(offset: index + replacement.length),
        composing: TextRange.empty,
      );
      target.spanController?.ensureSpansMatchText();
      target.onChanged?.call();
    }
    return true;
  }

  /// Applies an inline format action to every part the mark covers.
  bool applyFormat(String action, {required double baseFontSize}) {
    var changed = false;
    for (final span in spans) {
      final controller = span.spanController;
      if (controller == null || span.isEmpty) continue;
      controller.applyFormatAction(
        action,
        range: FormatRange(start: span.safeStart, end: span.safeEnd),
        baseFontSize: baseFontSize,
      );
      changed = true;
    }
    if (changed) {
      // Deferred: format actions run from a menu callback, while the tree may
      // still be locked.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final span in spans) {
          try {
            span.onChanged?.call();
          } catch (_) {}
        }
      });
    }
    return changed;
  }
}
