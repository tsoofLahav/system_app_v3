/// In-memory marker-text buffer — editor source of truth (v4 body, no header).
///
/// See [DocumentTextCodec] / editor/DOCUMENT_TEXT.md.
library;

import './document_codec.dart';
import './document_model.dart';
import './document_text_codec.dart';

enum DocPartKind {
  paragraph,
  heading,
  bulletList,
  orderedList,
  table,
  embed,
  spacer,
}

/// One top-level slice of [DocumentBuffer.text] (separated by `\n\n` in storage).
class DocPart {
  const DocPart({
    required this.key,
    required this.kind,
    required this.start,
    required this.end,
    this.objectId,
    this.objectType,
    this.headingLevel,
  });

  /// Stable for this indexing pass (`p0`, `p1`, … or `embed:42`).
  final String key;
  final DocPartKind kind;
  final int start;
  final int end;
  final int? objectId;
  final String? objectType;
  final int? headingLevel;

  int get length => end - start;

  String slice(String text) => text.substring(start, end);
}

class DocumentBuffer {
  DocumentBuffer(String text) : _text = text {
    reindex();
  }

  factory DocumentBuffer.empty() => DocumentBuffer('');

  factory DocumentBuffer.fromStored(String? raw) {
    if (raw == null || raw.trim().isEmpty) return DocumentBuffer.empty();
    if (DocumentTextCodec.isEditorText(raw)) {
      return DocumentBuffer(DocumentTextCodec.stripHeader(raw));
    }
    // Legacy v3 JSON or bare markers → normalize via codec.
    final doc = DocumentCodec.parse(raw);
    final wrapped = DocumentCodec.serialize(doc);
    return DocumentBuffer(DocumentTextCodec.stripHeader(wrapped));
  }

  String _text;
  List<DocPart> _parts = const [];

  String get text => _text;
  List<DocPart> get parts => _parts;

  String get stored => DocumentTextCodec.wrap(_text);

  static final _pointerRe = RegExp(
    r'^\[(INFO|TASK_LIST|IMAGE|GRAPH|EMBED)\s+id="(\d+)"\s*\]\s*$',
    caseSensitive: false,
  );
  static final _spacerRe = RegExp(
    r'^\[SPACER(?:\s+n="(\d+)")?\s*\]\s*$',
    caseSensitive: false,
  );
  static final _bulletFenceRe = RegExp(
    r'^\[BULLET_LIST\]\s*([\s\S]*?)\s*\[/BULLET_LIST\]\s*$',
    caseSensitive: false,
  );
  static final _orderedFenceRe = RegExp(
    r'^\[ORDERED_LIST\]\s*([\s\S]*?)\s*\[/ORDERED_LIST\]\s*$',
    caseSensitive: false,
  );
  static final _tableFenceRe = RegExp(
    r'^\[TABLE\]\s*([\s\S]*?)\s*\[/TABLE\]\s*$',
    caseSensitive: false,
  );
  static final _headingRe = RegExp(r'^(#{1,6})\s+(.*)$');

  void reindex() {
    final raw = _text;
    if (raw.isEmpty) {
      _parts = [
        DocPart(key: 'p0', kind: DocPartKind.paragraph, start: 0, end: 0),
      ];
      return;
    }

    final slices = <({int start, int end, String content})>[];
    final sep = RegExp(r'\n\n+');
    var start = 0;
    for (final match in sep.allMatches(raw)) {
      if (match.start > start) {
        slices.add((start: start, end: match.start, content: raw.substring(start, match.start)));
      }
      start = match.end;
    }
    if (start < raw.length) {
      slices.add((start: start, end: raw.length, content: raw.substring(start)));
    }

    final parts = <DocPart>[];
    var index = 0;
    for (final slice in slices) {
      final trimmed = slice.content.trim();
      if (trimmed.isEmpty) continue;

      final pointer = _pointerRe.firstMatch(trimmed);
      if (pointer != null) {
        final oid = int.parse(pointer.group(2)!);
        final type = _tagToType(pointer.group(1)!);
        parts.add(
          DocPart(
            key: 'embed:$oid',
            kind: DocPartKind.embed,
            start: slice.start,
            end: slice.end,
            objectId: oid,
            objectType: type,
          ),
        );
        index++;
        continue;
      }

      if (_spacerRe.hasMatch(trimmed)) {
        parts.add(
          DocPart(
            key: 'p$index',
            kind: DocPartKind.spacer,
            start: slice.start,
            end: slice.end,
          ),
        );
        index++;
        continue;
      }

      if (_bulletFenceRe.hasMatch(trimmed)) {
        parts.add(
          DocPart(
            key: 'p$index',
            kind: DocPartKind.bulletList,
            start: slice.start,
            end: slice.end,
          ),
        );
        index++;
        continue;
      }

      if (_orderedFenceRe.hasMatch(trimmed)) {
        parts.add(
          DocPart(
            key: 'p$index',
            kind: DocPartKind.orderedList,
            start: slice.start,
            end: slice.end,
          ),
        );
        index++;
        continue;
      }

      if (_tableFenceRe.hasMatch(trimmed)) {
        parts.add(
          DocPart(
            key: 'p$index',
            kind: DocPartKind.table,
            start: slice.start,
            end: slice.end,
          ),
        );
        index++;
        continue;
      }

      final heading = _headingRe.firstMatch(trimmed.split('\n').first);
      if (heading != null && !trimmed.contains('\n')) {
        parts.add(
          DocPart(
            key: 'p$index',
            kind: DocPartKind.heading,
            start: slice.start,
            end: slice.end,
            headingLevel: heading.group(1)!.length,
          ),
        );
        index++;
        continue;
      }

      parts.add(
        DocPart(
          key: 'p$index',
          kind: DocPartKind.paragraph,
          start: slice.start,
          end: slice.end,
        ),
      );
      index++;
    }

    if (parts.isEmpty) {
      parts.add(
        DocPart(key: 'p0', kind: DocPartKind.paragraph, start: 0, end: 0),
      );
    }

    // Drop blank/spacer neighbors pressed against embeds (fluent rule).
    final kept = _keptAfterDroppingBlankEmbedNeighbors(parts, raw);
    if (kept.length != parts.length) {
      _text = kept.map((p) => p.slice(raw)).join('\n\n');
      reindex(); // offsets after rewrite; drop already applied
      return;
    }
    _parts = parts;
  }

  List<DocPart> _keptAfterDroppingBlankEmbedNeighbors(
    List<DocPart> parts,
    String raw,
  ) {
    bool isBlank(DocPart p) {
      if (p.kind == DocPartKind.spacer) return true;
      if (p.kind != DocPartKind.paragraph) return false;
      return p.slice(raw).trim().isEmpty;
    }

    final out = <DocPart>[];
    for (var i = 0; i < parts.length; i++) {
      final p = parts[i];
      if (!isBlank(p)) {
        out.add(p);
        continue;
      }
      final prevEmbed = out.isNotEmpty && out.last.kind == DocPartKind.embed;
      final nextEmbed =
          i + 1 < parts.length && parts[i + 1].kind == DocPartKind.embed;
      if (prevEmbed || nextEmbed) continue;
      if (parts.length == 1) out.add(p);
    }
    return out.isEmpty && parts.isNotEmpty ? [parts.first] : out;
  }

  /// Replace absolute [start], [end) with [replacement] and reindex.
  void replaceRange(int start, int end, String replacement) {
    final s = start.clamp(0, _text.length);
    final e = end.clamp(0, _text.length);
    _text = _text.replaceRange(s, e, replacement);
    reindex();
  }

  /// Replace a part's full slice (by key). Returns false if key missing.
  bool replacePartSlice(String partKey, String newSlice) {
    final part = partByKey(partKey);
    if (part == null) return false;
    replaceRange(part.start, part.end, newSlice);
    return true;
  }

  DocPart? partByKey(String key) {
    for (final p in _parts) {
      if (p.key == key) return p;
    }
    return null;
  }

  DocPart? partAtOffset(int offset) {
    final o = offset.clamp(0, _text.length);
    for (final p in _parts) {
      if (o >= p.start && o <= p.end) return p;
    }
    return _parts.isEmpty ? null : _parts.last;
  }

  int localToGlobal(String partKey, int localOffset) {
    final part = partByKey(partKey);
    if (part == null) return 0;
    return part.start + localOffset.clamp(0, part.length);
  }

  int globalToLocal(String partKey, int globalOffset) {
    final part = partByKey(partKey);
    if (part == null) return 0;
    return (globalOffset - part.start).clamp(0, part.length);
  }

  DocPart? partBefore(String partKey) {
    final i = _parts.indexWhere((p) => p.key == partKey);
    if (i <= 0) return null;
    return _parts[i - 1];
  }

  DocPart? partAfter(String partKey) {
    final i = _parts.indexWhere((p) => p.key == partKey);
    if (i < 0 || i >= _parts.length - 1) return null;
    return _parts[i + 1];
  }

  void insertPointer({
    required int objectId,
    String? objectType,
    required int gapIndex,
  }) {
    final pointer = DocumentTextCodec.pointerLine(objectId, objectType);
    final chunks = _topLevelChunks();
    final gap = gapIndex.clamp(0, chunks.length);
    chunks.insert(gap, pointer);
    _text = chunks.join('\n\n');
    reindex();
  }

  void removePointer(int objectId) {
    final chunks = _topLevelChunks();
    chunks.removeWhere((c) {
      final m = _pointerRe.firstMatch(c.trim());
      return m != null && int.parse(m.group(2)!) == objectId;
    });
    _text = chunks.join('\n\n');
    reindex();
  }

  /// Move pointer to top-level gap (0 = before first part).
  bool movePointer(int objectId, int gapIndex) {
    final chunks = _topLevelChunks();
    final current = chunks.indexWhere((c) {
      final m = _pointerRe.firstMatch(c.trim());
      return m != null && int.parse(m.group(2)!) == objectId;
    });
    if (current < 0) return false;
    // Already sitting in this gap (immediately before or after the pointer).
    if (gapIndex == current || gapIndex == current + 1) return false;
    final pointer = chunks.removeAt(current).trim();
    var gap = gapIndex;
    if (current < gap) gap -= 1;
    gap = gap.clamp(0, chunks.length);
    chunks.insert(gap, pointer);
    _text = chunks.join('\n\n');
    reindex();
    return true;
  }

  /// Split text part at local [cut] and insert pointer between halves.
  bool splitPartAndInsertPointer({
    required String partKey,
    required int cut,
    required int objectId,
    String? objectType,
  }) {
    final part = partByKey(partKey);
    if (part == null) return false;
    if (part.kind != DocPartKind.paragraph && part.kind != DocPartKind.heading) {
      final i = _parts.indexWhere((p) => p.key == partKey);
      return movePointer(objectId, i < 0 ? 0 : i);
    }

    final slice = part.slice(_text);
    var beforeEnd = cut.clamp(0, slice.length);
    var afterStart = beforeEnd;
    while (beforeEnd > 0 && slice[beforeEnd - 1] == '\n') {
      beforeEnd--;
    }
    while (afterStart < slice.length && slice[afterStart] == '\n') {
      afterStart++;
    }
    final before = slice.substring(0, beforeEnd);
    final after = slice.substring(afterStart);
    if (before.isEmpty) {
      final i = _parts.indexWhere((p) => p.key == partKey);
      return movePointer(objectId, i < 0 ? 0 : i);
    }
    if (after.isEmpty) {
      final i = _parts.indexWhere((p) => p.key == partKey);
      return movePointer(objectId, i < 0 ? 0 : i + 1);
    }

    final pointer = DocumentTextCodec.pointerLine(objectId, objectType);
    final partIndex = _topLevelChunks().indexWhere(
      (c) => c == slice || c.trim() == slice.trim(),
    );

    // Build new chunk list: remove old pointer, split target, insert pointer.
    final chunks = _topLevelChunks()
        .where((c) {
          final m = _pointerRe.firstMatch(c.trim());
          return !(m != null && int.parse(m.group(2)!) == objectId);
        })
        .toList();
    var target = partIndex;
    if (target < 0) {
      target = chunks.indexWhere((c) => c == slice || c.trim() == slice.trim());
    }
    if (target < 0) {
      chunks.add(pointer);
      _text = chunks.join('\n\n');
      reindex();
      return true;
    }

    final next = <String>[];
    for (var i = 0; i < chunks.length; i++) {
      if (i != target) {
        next.add(chunks[i]);
        continue;
      }
      next.add(before);
      next.add(pointer);
      next.add(after);
    }
    _text = next.join('\n\n');
    reindex();
    return true;
  }

  List<String> _topLevelChunks() {
    if (_text.isEmpty) return [];
    return _text.split(RegExp(r'\n\n+')).where((p) => p.isNotEmpty).toList();
  }

  /// View model for widgets that still expect [RichDocument] (not SoT).
  ///
  /// Node [DocumentNode.id] values match [DocPart.key] so controllers stay stable
  /// across in-place text edits that only shift offsets.
  RichDocument toRichDocument() {
    final blocks = <DocumentNode>[];
    for (final part in _parts) {
      final slice = part.slice(_text);
      switch (part.kind) {
        case DocPartKind.paragraph:
        case DocPartKind.spacer:
          blocks.add(ParagraphNode(id: part.key, text: slice));
        case DocPartKind.heading:
          final m = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(slice.trim());
          blocks.add(
            HeadingNode(
              id: part.key,
              level: part.headingLevel ?? m?.group(1)?.length ?? 1,
              text: m?.group(2) ?? slice.replaceFirst(RegExp(r'^#+\s*'), ''),
            ),
          );
        case DocPartKind.bulletList:
        case DocPartKind.orderedList:
          final doc = DocumentTextCodec.parse(DocumentTextCodec.wrap(slice));
          final list = doc.blocks.whereType<ListNode>().firstOrNull;
          if (list != null) {
            blocks.add(
              ListNode(
                id: part.key,
                listStyle: list.listStyle,
                items: list.items,
              ),
            );
          }
        case DocPartKind.table:
          final doc = DocumentTextCodec.parse(DocumentTextCodec.wrap(slice));
          final table = doc.blocks.whereType<TableNode>().firstOrNull;
          if (table != null) {
            blocks.add(TableNode(id: part.key, rows: table.rows));
          }
        case DocPartKind.embed:
          blocks.add(
            EmbedNode(
              id: part.key,
              objectId: part.objectId ?? 0,
              objectType: part.objectType,
            ),
          );
      }
    }
    if (blocks.isEmpty) {
      blocks.add(ParagraphNode(id: 'p0', text: ''));
    }
    return RichDocument(version: RichDocument.documentVersion, blocks: blocks);
  }

  /// Apply a RichDocument view back into the buffer (structural migrations).
  void loadFromRichDocument(RichDocument doc, {Map<int, String>? objectTypes}) {
    _text = DocumentTextCodec.stripHeader(
      DocumentTextCodec.serialize(doc, objectTypes: objectTypes),
    );
    reindex();
  }

  DocumentBuffer copy() => DocumentBuffer(_text);

  static String? _tagToType(String tag) => switch (tag.toUpperCase()) {
        'INFO' => 'info',
        'TASK_LIST' => 'task_list',
        'IMAGE' => 'image',
        'GRAPH' => 'graph',
        _ => null,
      };
}
