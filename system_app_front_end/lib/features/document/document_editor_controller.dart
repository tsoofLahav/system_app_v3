import 'package:flutter/material.dart';

import 'document_codec.dart';
import 'inline_document_model.dart';

/// Callbacks exposed to [DocumentInsertBar] while a file is being edited.
class DocumentEditorController {
  DocumentEditorController({
    required this.fileId,
    required this.insertAtCaret,
    required this.focusCaret,
  });

  final int fileId;
  final Future<void> Function(String action) insertAtCaret;
  final VoidCallback focusCaret;
}

class DocumentEditorRegistry {
  DocumentEditorRegistry._();

  static DocumentEditorController? active;
  static int? get activeFileId => active?.fileId;

  static void register(DocumentEditorController controller) {
    active = controller;
  }

  static void unregister(int fileId) {
    if (active?.fileId == fileId) active = null;
  }
}

/// Builds alternating text segments and inline embed widgets from [InlineDocument].
List<InlineSegment> splitInlineSegments(InlineDocument doc) {
  if (doc.text.isEmpty && doc.embeds.isEmpty) {
    return [InlineTextSegment(start: 0, end: 0, spans: doc.spans)];
  }
  final sorted = [...doc.embeds]..sort((a, b) => a.offset.compareTo(b.offset));
  final segments = <InlineSegment>[];
  var cursor = 0;
  for (final embed in sorted) {
    final pos = embed.offset.clamp(0, doc.text.length);
    if (pos > cursor) {
      segments.add(
        InlineTextSegment(
          start: cursor,
          end: pos,
          spans: _spansInRange(doc.spans, cursor, pos),
        ),
      );
    }
    segments.add(InlineEmbedSegment(embed: embed));
    cursor = pos + 1;
  }
  if (cursor < doc.text.length) {
    segments.add(
      InlineTextSegment(
        start: cursor,
        end: doc.text.length,
        spans: _spansInRange(doc.spans, cursor, doc.text.length),
      ),
    );
  }
  if (segments.isEmpty) {
    segments.add(InlineTextSegment(start: 0, end: 0, spans: const []));
  }
  return segments;
}

List<TextSpanMark> _spansInRange(List<TextSpanMark> spans, int start, int end) {
  return [
    for (final s in spans)
      if (s.end > start && s.start < end)
        TextSpanMark(
          start: s.start - start,
          end: s.end - start,
          bold: s.bold,
          italic: s.italic,
          underline: s.underline,
          size: s.size,
        ),
  ];
}

sealed class InlineSegment {}

class InlineTextSegment extends InlineSegment {
  InlineTextSegment({
    required this.start,
    required this.end,
    required this.spans,
  });

  final int start;
  final int end;
  final List<TextSpanMark> spans;

  String textSlice(InlineDocument doc) =>
      doc.text.substring(start, end.clamp(0, doc.text.length));
}

class InlineEmbedSegment extends InlineSegment {
  InlineEmbedSegment({required this.embed});

  final DocumentEmbed embed;
}

/// Rebuild document text/spans from edited segments (embed offsets unchanged).
InlineDocument mergeTextSegments(
  InlineDocument base,
  List<InlineTextSegment> textSegments,
) {
  final buffer = StringBuffer();
  final spans = <TextSpanMark>[];
  final embeds = [...base.embeds]..sort((a, b) => a.offset.compareTo(b.offset));
  var cursor = 0;
  var embedIndex = 0;

  for (final segment in splitInlineSegments(base)) {
    if (segment is InlineTextSegment) {
      final updated = textSegments.firstWhere(
        (s) => s.start == segment.start && s.end == segment.end,
        orElse: () => segment,
      );
      final slice = updated.textSlice(base);
      for (final span in updated.spans) {
        spans.add(span.shift(cursor));
      }
      buffer.write(slice);
      cursor += slice.length;
    } else if (segment is InlineEmbedSegment) {
      if (embedIndex < embeds.length) {
        embeds[embedIndex] = embeds[embedIndex].copyWith(offset: cursor);
        embedIndex++;
      }
      buffer.write(InlineDocument.embedChar);
      cursor += 1;
    }
  }

  return base.copyWith(text: buffer.toString(), spans: spans, embeds: embeds);
}
