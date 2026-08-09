/// Pure structural helpers on a [RichDocument] **view** of marker text.
///
/// Editor SoT is [`DocumentBuffer`](../model/document_buffer.dart). The editor
/// folds session results via `loadFromRichDocument` (or uses buffer move/split
/// directly for embeds). No widgets, no controllers, no API calls.
library;

import '../model/document_codec.dart';
import '../model/document_model.dart';
import '../model/document_text_codec.dart';
import './document_structure_prune.dart';
import './document_text_flow.dart';

/// Outcome of a structural edit. [changed] is false for no-ops.
class DocumentSessionResult {
  const DocumentSessionResult({
    required this.doc,
    required this.changed,
    this.landingBlockId,
    this.focusSegmentId,
    this.focusOffset = 0,
    this.removedObjectId,
    this.insertGapIndex,
  });

  final RichDocument doc;
  final bool changed;

  /// Block to focus after commit (first part of that block).
  final String? landingBlockId;

  /// Prefer this segment over [landingBlockId] when set.
  final String? focusSegmentId;
  final int focusOffset;

  /// Embed object id removed from the tree — caller cascade-deletes via API.
  final int? removedObjectId;

  /// For insert-at-caret: gap index where the new block should go (no doc change
  /// when the split was only computing a gap, or after an in-doc split).
  final int? insertGapIndex;

  static DocumentSessionResult unchanged(RichDocument doc) =>
      DocumentSessionResult(doc: doc, changed: false);
}

/// Structural pipeline: mutate blocks → coalesce when needed → return focus hint.
class DocumentSession {
  const DocumentSession();

  /// Split a paragraph/heading at [cut] using live text, or return a gap index
  /// with no split when the caret is at a boundary / non-text block.
  ///
  /// [liveText] / [liveSpans] should come from the focused controller when it
  /// may be ahead of [doc].
  DocumentSessionResult prepareInsertSite({
    required RichDocument doc,
    required String? focusedSegmentId,
    required int fallbackBlockIndex,
    required String? Function(String blockId) liveTextOf,
    required List<TextSpanMark>? Function(String blockId) liveSpansOf,
    required int Function(String segmentId) caretOffsetOf,
  }) {
    if (focusedSegmentId == null) {
      final gap = (fallbackBlockIndex + 1).clamp(0, doc.blocks.length);
      return DocumentSessionResult(
        doc: doc,
        changed: false,
        insertGapIndex: gap,
      );
    }

    final hash = focusedSegmentId.indexOf('#');
    final blockId =
        hash < 0 ? focusedSegmentId : focusedSegmentId.substring(0, hash);
    final i = doc.blocks.indexWhere((b) => b.id == blockId);
    if (i < 0) {
      final gap = (fallbackBlockIndex + 1).clamp(0, doc.blocks.length);
      return DocumentSessionResult(
        doc: doc,
        changed: false,
        insertGapIndex: gap,
      );
    }

    if (hash >= 0) {
      return DocumentSessionResult(
        doc: doc,
        changed: false,
        insertGapIndex: (i + 1).clamp(0, doc.blocks.length),
      );
    }

    final block = doc.blocks[i];
    if (block is! ParagraphNode && block is! HeadingNode) {
      return DocumentSessionResult(
        doc: doc,
        changed: false,
        insertGapIndex: (i + 1).clamp(0, doc.blocks.length),
      );
    }

    final fromController = liveTextOf(blockId);
    final liveText = fromController ??
        (block is ParagraphNode ? block.text : (block as HeadingNode).text);
    final liveSpans = liveSpansOf(blockId) ??
        (block is ParagraphNode
            ? block.spans
            : (block as HeadingNode).spans);
    final cut = caretOffsetOf(focusedSegmentId).clamp(0, liveText.length);

    if (cut <= 0) {
      return DocumentSessionResult(doc: doc, changed: false, insertGapIndex: i);
    }
    if (cut >= liveText.length) {
      return DocumentSessionResult(
        doc: doc,
        changed: false,
        insertGapIndex: (i + 1).clamp(0, doc.blocks.length),
      );
    }

    final beforeText = liveText.substring(0, cut);
    final afterText = liveText.substring(cut);
    final beforeSpans = spansBefore(liveSpans, cut);
    final afterSpans = spansAfter(liveSpans, cut);
    final afterId = DocumentCodec.newId('b');

    final DocumentNode beforeNode;
    final DocumentNode afterNode;
    if (block is HeadingNode) {
      beforeNode = block.copyWith(text: beforeText, spans: beforeSpans);
      afterNode = HeadingNode(
        id: afterId,
        level: block.level,
        text: afterText,
        spans: afterSpans,
      );
    } else {
      beforeNode = (block as ParagraphNode).copyWith(
        text: beforeText,
        spans: beforeSpans,
      );
      afterNode = ParagraphNode(id: afterId, text: afterText, spans: afterSpans);
    }

    var next = DocumentCodec.replaceBlock(doc, blockId, beforeNode);
    next = DocumentCodec.insertBlock(next, i + 1, afterNode);
    return DocumentSessionResult(
      doc: next,
      changed: true,
      insertGapIndex: i + 1,
      landingBlockId: afterId,
    );
  }

  DocumentSessionResult removeStructureBlock(RichDocument doc, String blockId) {
    final index = doc.blocks.indexWhere((b) => b.id == blockId);
    if (index < 0) return DocumentSessionResult.unchanged(doc);
    final blocks = [...doc.blocks]..removeAt(index);
    if (blocks.isEmpty) {
      blocks.add(ParagraphNode(id: DocumentCodec.newId('b'), text: ''));
    }
    final coalesced = DocumentCodec.coalesceAdjacentParagraphs(
      doc.copyWith(blocks: blocks),
    );
    final edge = _edgeLandingAfterRemoval(doc, index, coalesced);
    return DocumentSessionResult(
      doc: coalesced,
      changed: true,
      landingBlockId: edge.landingBlockId,
      focusSegmentId: edge.focusSegmentId,
      focusOffset: edge.focusOffset,
    );
  }

  /// Removes an embed from the tree. Caller deletes the object row via API.
  DocumentSessionResult deleteEmbedBlock(RichDocument doc, String blockId) {
    final index = doc.blocks.indexWhere((b) => b.id == blockId);
    if (index < 0) return DocumentSessionResult.unchanged(doc);
    final block = doc.blocks[index];
    if (block is! EmbedNode) return DocumentSessionResult.unchanged(doc);

    final blocks = [...doc.blocks]..removeAt(index);
    if (blocks.isEmpty) {
      blocks.add(ParagraphNode(id: DocumentCodec.newId('b'), text: ''));
    }
    final coalesced = DocumentCodec.coalesceAdjacentParagraphs(
      doc.copyWith(blocks: blocks),
    );
    final edge = _edgeLandingAfterRemoval(doc, index, coalesced);
    return DocumentSessionResult(
      doc: coalesced,
      changed: true,
      landingBlockId: edge.landingBlockId,
      focusSegmentId: edge.focusSegmentId,
      focusOffset: edge.focusOffset,
      removedObjectId: block.objectId,
    );
  }

  /// Caret at the **end** of the text that was above the removed block
  /// (edge landing). Falls back to the first remaining block at offset 0.
  static ({
    String landingBlockId,
    String? focusSegmentId,
    int focusOffset,
  }) _edgeLandingAfterRemoval(
    RichDocument before,
    int removedIndex,
    RichDocument coalesced,
  ) {
    if (removedIndex > 0) {
      final prev = before.blocks[removedIndex - 1];
      if (prev is ParagraphNode || prev is HeadingNode) {
        final stillThere = coalesced.blocks.any((b) => b.id == prev.id);
        if (stillThere) {
          final text =
              prev is ParagraphNode ? prev.text : (prev as HeadingNode).text;
          return (
            landingBlockId: prev.id,
            focusSegmentId: paragraphSegmentId(prev.id),
            focusOffset: text.length,
          );
        }
      }
    }
    final landing =
        removedIndex.clamp(0, coalesced.blocks.length - 1);
    final block = coalesced.blocks[landing];
    if (block is ParagraphNode || block is HeadingNode) {
      return (
        landingBlockId: block.id,
        focusSegmentId: paragraphSegmentId(block.id),
        focusOffset: 0,
      );
    }
    return (
      landingBlockId: block.id,
      focusSegmentId: null,
      focusOffset: 0,
    );
  }

  DocumentSessionResult exitListBelow(
    RichDocument doc,
    String blockId,
    int emptyItemIndex,
  ) {
    final index = doc.blocks.indexWhere((b) => b.id == blockId);
    if (index < 0) return DocumentSessionResult.unchanged(doc);
    final block = doc.blocks[index];
    if (block is! ListNode) return DocumentSessionResult.unchanged(doc);

    var items = [...block.items];
    if (emptyItemIndex >= 0 && emptyItemIndex < items.length) {
      items.removeAt(emptyItemIndex);
    }

    final newParagraphId = DocumentCodec.newId('b');
    final blocks = [...doc.blocks];
    if (items.isEmpty) {
      blocks[index] = ParagraphNode(id: newParagraphId, text: '');
    } else {
      blocks[index] = block.copyWith(items: items);
      blocks.insert(index + 1, ParagraphNode(id: newParagraphId, text: ''));
    }

    return DocumentSessionResult(
      doc: doc.copyWith(blocks: blocks),
      changed: true,
      focusSegmentId: paragraphSegmentId(newParagraphId),
      landingBlockId: newParagraphId,
    );
  }

  DocumentSessionResult exitTableBelow(
    RichDocument doc,
    String blockId,
    int emptyRowIndex,
  ) {
    final index = doc.blocks.indexWhere((b) => b.id == blockId);
    if (index < 0) return DocumentSessionResult.unchanged(doc);
    final block = doc.blocks[index];
    if (block is! TableNode) return DocumentSessionResult.unchanged(doc);

    var rows = [
      for (final row in block.rows)
        [for (final cell in row) cell],
    ];
    if (emptyRowIndex >= 0 && emptyRowIndex < rows.length) {
      rows.removeAt(emptyRowIndex);
    }

    final newParagraphId = DocumentCodec.newId('b');
    final blocks = [...doc.blocks];
    final hasContent = rows.any(
      (row) => row.any((cell) => cell.text.trim().isNotEmpty),
    );

    if (!hasContent || rows.isEmpty) {
      blocks[index] = ParagraphNode(id: newParagraphId, text: '');
    } else {
      blocks[index] = block.copyWith(rows: rows);
      blocks.insert(index + 1, ParagraphNode(id: newParagraphId, text: ''));
    }

    return DocumentSessionResult(
      doc: doc.copyWith(blocks: blocks),
      changed: true,
      focusSegmentId: paragraphSegmentId(newParagraphId),
      landingBlockId: newParagraphId,
    );
  }

  DocumentSessionResult exitEmbedBelow(RichDocument doc, String blockId) {
    final index = doc.blocks.indexWhere((b) => b.id == blockId);
    if (index < 0) return DocumentSessionResult.unchanged(doc);
    final block = doc.blocks[index];
    if (block is! EmbedNode) return DocumentSessionResult.unchanged(doc);

    final newParagraphId = DocumentCodec.newId('b');
    final blocks = [...doc.blocks];
    blocks.insert(index + 1, ParagraphNode(id: newParagraphId, text: ''));

    return DocumentSessionResult(
      doc: doc.copyWith(blocks: blocks),
      changed: true,
      focusSegmentId: paragraphSegmentId(newParagraphId),
      landingBlockId: newParagraphId,
    );
  }

  /// Doc-only half of empty task-list exit when no tasks remain: replace embed
  /// with an empty paragraph. Caller deletes the object via API.
  DocumentSessionResult replaceEmbedWithParagraph(
    RichDocument doc,
    String blockId,
  ) {
    final index = doc.blocks.indexWhere((b) => b.id == blockId);
    if (index < 0) return DocumentSessionResult.unchanged(doc);
    final block = doc.blocks[index];
    if (block is! EmbedNode) return DocumentSessionResult.unchanged(doc);

    final newParagraphId = DocumentCodec.newId('b');
    final blocks = [...doc.blocks];
    blocks[index] = ParagraphNode(id: newParagraphId, text: '');
    final coalesced = DocumentCodec.coalesceAdjacentParagraphs(
      doc.copyWith(blocks: blocks),
    );

    return DocumentSessionResult(
      doc: coalesced,
      changed: true,
      focusSegmentId: paragraphSegmentId(newParagraphId),
      landingBlockId: newParagraphId,
      removedObjectId: block.objectId,
    );
  }

  DocumentSessionResult moveEmbedToGap(
    RichDocument doc,
    String blockId,
    int gapIndex,
  ) {
    EmbedNode? embed;
    for (final b in doc.blocks) {
      if (b is EmbedNode && b.id == blockId) {
        embed = b;
        break;
      }
    }
    if (embed == null) return DocumentSessionResult.unchanged(doc);

    // Marker-text SoT: cut/paste the pointer among top-level parts.
    final before = DocumentCodec.moveEmbedToGap(doc, blockId, gapIndex);
    if (identical(before, doc)) return DocumentSessionResult.unchanged(doc);
    final text = DocumentTextCodec.serialize(before);
    final normalized = DocumentTextCodec.parse(text);
    final landing = _embedBlockIdForObject(normalized, embed.objectId) ?? blockId;
    return DocumentSessionResult(
      doc: DocumentCodec.coalesceAdjacentParagraphs(normalized),
      changed: true,
      landingBlockId: landing,
    );
  }

  /// Split paragraph/heading at [cut] and place [embedBlockId] between halves.
  ///
  /// Uses string cut/paste of the pointer token so surrounding text stays one
  /// unit in the marker-text source of truth (no empty neighbor stubs).
  DocumentSessionResult moveEmbedSplittingText({
    required RichDocument doc,
    required String embedBlockId,
    required int targetIndex,
    required int cut,
    String? liveText,
    List<TextSpanMark>? liveSpans,
  }) {
    if (targetIndex < 0 || targetIndex >= doc.blocks.length) {
      return DocumentSessionResult.unchanged(doc);
    }
    EmbedNode? embed;
    for (final b in doc.blocks) {
      if (b is EmbedNode && b.id == embedBlockId) {
        embed = b;
        break;
      }
    }
    if (embed == null) return DocumentSessionResult.unchanged(doc);

    final block = doc.blocks[targetIndex];
    if (block is! ParagraphNode && block is! HeadingNode) {
      return moveEmbedToGap(doc, embedBlockId, targetIndex);
    }

    final text = liveText ??
        (block is ParagraphNode ? block.text : (block as HeadingNode).text);
    final clamped = cut.clamp(0, text.length);
    if (clamped <= 0) return moveEmbedToGap(doc, embedBlockId, targetIndex);
    if (clamped >= text.length) {
      return moveEmbedToGap(doc, embedBlockId, targetIndex + 1);
    }

    // Apply live text onto a copy, then serialize and split that part in text.
    var working = doc;
    if (liveText != null) {
      if (block is ParagraphNode) {
        working = DocumentCodec.replaceBlock(
          working,
          block.id,
          block.copyWith(text: liveText, spans: liveSpans ?? block.spans),
        );
      } else if (block is HeadingNode) {
        working = DocumentCodec.replaceBlock(
          working,
          block.id,
          block.copyWith(text: liveText, spans: liveSpans ?? block.spans),
        );
      }
    }

    // Block index of the target after removing the embed (for part alignment).
    final embedIndex = working.blocks.indexWhere((b) => b.id == embedBlockId);
    var partIndex = targetIndex;
    if (embedIndex >= 0 && embedIndex < targetIndex) {
      partIndex -= 1;
    }
    working = DocumentCodec.removeBlock(working, embedBlockId);

    final wrapped = DocumentTextCodec.serialize(working);
    final pointer = DocumentTextCodec.pointerLine(
      embed.objectId,
      embed.objectType,
    );
    final nextText = DocumentTextCodec.splitPartAndInsertPointer(
      wrapped,
      partIndex: partIndex.clamp(0, 999999),
      cut: clamped,
      pointer: pointer,
      removeObjectId: embed.objectId,
    );
    final normalized = DocumentTextCodec.parse(nextText);
    final landing =
        _embedBlockIdForObject(normalized, embed.objectId) ?? embedBlockId;
    return DocumentSessionResult(
      doc: DocumentCodec.coalesceAdjacentParagraphs(normalized),
      changed: true,
      landingBlockId: landing,
    );
  }

  static String? _embedBlockIdForObject(RichDocument doc, int objectId) {
    for (final block in doc.blocks) {
      if (block is EmbedNode && block.objectId == objectId) return block.id;
    }
    return null;
  }

  DocumentSessionResult applyPrune({
    required RichDocument doc,
    required Set<String> fullyEmptied,
    required bool spansParts,
  }) {
    final pruned = pruneFullyMarkedStructures(
      blocks: doc.blocks,
      fullyEmptied: fullyEmptied,
      spansParts: spansParts,
    );
    if (!pruned.changed) return DocumentSessionResult.unchanged(doc);
    final coalesced = DocumentCodec.coalesceAdjacentParagraphs(
      doc.copyWith(blocks: pruned.blocks),
    );
    final landing =
        pruned.firstRemovedIndex.clamp(0, coalesced.blocks.length - 1);
    return DocumentSessionResult(
      doc: coalesced,
      changed: true,
      landingBlockId: coalesced.blocks[landing].id,
    );
  }

  static List<TextSpanMark> spansBefore(List<TextSpanMark> spans, int cut) {
    return [
      for (final s in spans)
        if (s.end <= cut)
          s
        else if (s.start < cut)
          s.copyWith(end: cut),
    ];
  }

  static List<TextSpanMark> spansAfter(List<TextSpanMark> spans, int cut) {
    return [
      for (final s in spans)
        if (s.start >= cut)
          s.copyWith(start: s.start - cut, end: s.end - cut)
        else if (s.end > cut)
          s.copyWith(start: 0, end: s.end - cut),
    ];
  }
}
