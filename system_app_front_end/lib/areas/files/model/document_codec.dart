import 'dart:convert';
import 'dart:math';

import './document_model.dart';
import './document_text_codec.dart';

class DocumentCodec {
  static const embedChar = '\uFFFC';

  static String newId([String prefix = 'b']) =>
      '$prefix${Random().nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  static RichDocument empty() =>
      const RichDocument(version: RichDocument.documentVersion, blocks: []);

  static RichDocument parse(String? raw) {
    final body = raw?.trim() ?? '';
    if (body.isEmpty) return empty();
    if (DocumentTextCodec.isEditorText(body)) {
      return DocumentTextCodec.parse(body);
    }
    final trimmed = body.trimLeft();
    if (trimmed.startsWith('{')) {
      try {
        final data = jsonDecode(body);
        if (data is Map<String, dynamic>) {
          final version = data['version'] as int? ?? 1;
          if (version >= 3 && data['blocks'] is List) {
            return _fromV3(data);
          }
          if (version >= 2 && data.containsKey('text')) {
            return _migrateV2ToV3(data);
          }
          if (data['nodes'] is List) {
            return _migrateV1Nodes(data['nodes'] as List);
          }
        }
      } catch (_) {}
    }
    // Bare marker text (or non-JSON body).
    return DocumentTextCodec.parse(body);
  }

  /// Persist as v4 editor text (pointer embeds). [objectTypes] labels pointers.
  static String serialize(
    RichDocument doc, {
    Map<int, String>? objectTypes,
  }) {
    final types = {
      ...?objectTypes,
      for (final b in doc.blocks)
        if (b is EmbedNode && b.objectType != null) b.objectId: b.objectType!,
    };
    return DocumentTextCodec.serialize(doc, objectTypes: types);
  }

  static DocumentNode nodeFromJson(Map<String, dynamic> json) {
    final type = json['type'] as String? ?? 'paragraph';
    final id = json['id'] as String? ?? newId('b');
    switch (type) {
      case 'heading':
        return HeadingNode(
          id: id,
          level: json['level'] as int? ?? 1,
          text: json['text'] as String? ?? '',
          spans: _spansFrom(json['spans']),
        );
      case 'list':
      case 'bullet_list':
      case 'ordered_list':
        return ListNode(
          id: id,
          listStyle: _listStyleFromJson(json, type),
          items: [
            for (final item in json['items'] as List? ?? const [])
              if (item is Map<String, dynamic>) ListItem.fromJson(item),
          ],
        );
      case 'table':
        return TableNode(
          id: id,
          rows: [
            for (final row in json['rows'] as List? ?? const [])
              if (row is List)
                [for (final cell in row) DocumentTableCell.fromJson(cell)],
          ],
        );
      case 'embed':
        return EmbedNode(
          id: id,
          objectId: json['object_id'] as int? ?? 0,
          objectType: json['object_type'] as String?,
        );
      default:
        return ParagraphNode(
          id: id,
          text: json['text'] as String? ?? '',
          spans: _spansFrom(json['spans']),
        );
    }
  }

  static RichDocument _fromV3(Map<String, dynamic> data) {
    final blocks = [
      for (final item in data['blocks'] as List? ?? const [])
        if (item is Map<String, dynamic>) nodeFromJson(item),
    ];
    if (blocks.isEmpty) {
      blocks.add(ParagraphNode(id: newId('b'), text: ''));
    }
    return RichDocument(version: RichDocument.documentVersion, blocks: blocks);
  }

  static List<TextSpanMark> _spansFrom(dynamic raw) => [
    for (final s in raw as List? ?? const [])
      if (s is Map<String, dynamic>) TextSpanMark.fromJson(s),
  ];

  static String _listStyleFromJson(Map<String, dynamic> json, String type) {
    if (type == 'ordered_list') return 'numbered';
    if (type == 'bullet_list') return 'bullet';
    final style = json['list_style'] as String? ?? 'bullet';
    if (style == 'ordered') return 'numbered';
    return style;
  }

  static RichDocument _migratePlain(String body) {
    final blocks = <DocumentNode>[];
    for (final line in body.split('\n')) {
      final stripped = line.trim();
      final task = RegExp(r'^\{\{task:(\d+)\}\}$').firstMatch(stripped);
      if (task != null) {
        blocks.add(EmbedNode(id: newId('b'), objectId: int.parse(task.group(1)!)));
        continue;
      }
      final info = RegExp(r'^\{\{info:(\d+)\}\}$').firstMatch(stripped);
      if (info != null) {
        blocks.add(EmbedNode(id: newId('b'), objectId: int.parse(info.group(1)!)));
        continue;
      }
      if (line.isNotEmpty || blocks.isNotEmpty) {
        blocks.add(ParagraphNode(id: newId('b'), text: line));
      }
    }
    if (blocks.isEmpty) {
      blocks.add(ParagraphNode(id: newId('b'), text: ''));
    }
    return RichDocument(version: RichDocument.documentVersion, blocks: blocks);
  }

  static RichDocument _migrateV1Nodes(List nodes) {
    final blocks = <DocumentNode>[];
    for (final raw in nodes) {
      if (raw is! Map<String, dynamic>) continue;
      blocks.add(nodeFromJson(_v1NodeToV3(raw)));
    }
    return RichDocument(version: RichDocument.documentVersion, blocks: blocks);
  }

  static Map<String, dynamic> _v1NodeToV3(Map<String, dynamic> node) {
    final type = node['type'];
    if (type == 'object') {
      return {
        'id': node['id'] ?? newId('b'),
        'type': 'embed',
        'object_id': node['object_id'],
      };
    }
    if (type == 'list') {
      final items = node['items'] as List? ?? const [];
      return {
        'id': node['id'] ?? newId('b'),
        'type': 'list',
        'list_style': node['list_style'] ?? 'bullet',
        'items': [
          for (var i = 0; i < items.length; i++)
            {
              'id': newId('li'),
              'text': items[i].toString(),
              'indent': 0,
              'spans': [],
            },
        ],
      };
    }
    if (type == 'image' || type == 'graph') {
      return {
        'id': node['id'] ?? newId('b'),
        'type': 'embed',
        'object_id': 0,
      };
    }
    return {
      'id': node['id'] ?? newId('b'),
      'type': type == 'paragraph' ? 'paragraph' : type,
      'text': node['text'] ?? '',
      'spans': node['spans'] ?? [],
      if (type == 'heading') 'level': node['level'] ?? 1,
      if (type == 'table') 'rows': node['rows'] ?? [['', '']],
    };
  }

  static RichDocument _migrateV2ToV3(Map<String, dynamic> data) {
    final text = data['text'] as String? ?? '';
    final embeds = [
      for (final e in data['embeds'] as List? ?? const [])
        if (e is Map<String, dynamic>) e,
    ]..sort((a, b) => (a['offset'] as int? ?? 0).compareTo(b['offset'] as int? ?? 0));

    final blocks = <DocumentNode>[];
    var pos = 0;
    for (final embed in embeds) {
      final offset = embed['offset'] as int? ?? 0;
      if (offset > pos) {
        final segment = text.substring(pos, offset);
        if (segment.isNotEmpty) {
          blocks.add(ParagraphNode(id: newId('b'), text: segment));
        }
      }
      if (embed['kind'] == 'object') {
        blocks.add(
          EmbedNode(id: newId('b'), objectId: embed['object_id'] as int),
        );
      }
      pos = offset + 1;
    }
    if (pos < text.length) {
      blocks.add(ParagraphNode(id: newId('b'), text: text.substring(pos).replaceAll(embedChar, '')));
    }
    if (blocks.isEmpty) {
      blocks.add(ParagraphNode(id: newId('b'), text: ''));
    }
    return RichDocument(version: RichDocument.documentVersion, blocks: blocks);
  }

  static RichDocument insertEmbedBlock(
    RichDocument doc,
    int objectId, {
    int? blockIndex,
    String? blockId,
  }) {
    final blocks = [...doc.blocks];
    final index = blockIndex == null ? blocks.length : blockIndex.clamp(0, blocks.length);
    blocks.insert(
      index,
      EmbedNode(id: blockId ?? newId('b'), objectId: objectId),
    );
    return doc.copyWith(blocks: blocks);
  }

  /// Moves an embed into the gap *before* [gapIndex] in the current list
  /// (`0` = before the first block, `blocks.length` = after the last).
  ///
  /// No-ops when the embed is already adjacent to that gap.
  static RichDocument moveEmbedToGap(
    RichDocument doc,
    String blockId,
    int gapIndex,
  ) {
    final blocks = [...doc.blocks];
    final current = blocks.indexWhere((b) => b.id == blockId);
    if (current < 0) return doc;
    final gap = gapIndex.clamp(0, blocks.length);
    // Already sitting in this gap (immediately before or after the embed).
    if (gap == current || gap == current + 1) return doc;
    final block = blocks.removeAt(current);
    var insertAt = gap;
    if (current < gap) insertAt -= 1;
    blocks.insert(insertAt.clamp(0, blocks.length), block);
    return doc.copyWith(blocks: blocks);
  }

  /// Moves an embed so it occupies [newIndex] in the resulting document.
  static RichDocument moveEmbedBlock(
    RichDocument doc,
    String blockId,
    int newIndex,
  ) {
    final blocks = [...doc.blocks];
    final current = blocks.indexWhere((b) => b.id == blockId);
    if (current < 0) return doc;
    final block = blocks.removeAt(current);
    final index = newIndex.clamp(0, blocks.length);
    if (index == current) {
      blocks.insert(current, block);
      return doc;
    }
    blocks.insert(index, block);
    return doc.copyWith(blocks: blocks);
  }

  static RichDocument removeBlock(RichDocument doc, String blockId) {
    return doc.copyWith(blocks: doc.blocks.where((b) => b.id != blockId).toList());
  }

  static RichDocument replaceBlock(RichDocument doc, String blockId, DocumentNode replacement) {
    return doc.copyWith(
      blocks: [
        for (final block in doc.blocks)
          if (block.id == blockId) replacement else block,
      ],
    );
  }

  static RichDocument insertBlock(RichDocument doc, int index, DocumentNode block) {
    final blocks = [...doc.blocks];
    blocks.insert(index.clamp(0, blocks.length), block);
    return doc.copyWith(blocks: blocks);
  }

  /// True for empty or whitespace/`\n`-only paragraph text (visual blank stub).
  static bool isBlankParagraphText(String text) => text.trim().isEmpty;

  /// Merges adjacent paragraphs into one continuous block.
  ///
  /// Blank paragraph neighbors (empty or `\n`/whitespace-only) are dropped —
  /// including stubs next to embeds — so move/delete does not leave a gap.
  static RichDocument coalesceAdjacentParagraphs(RichDocument doc) {
    final blocks = <DocumentNode>[];
    ParagraphNode? run;

    void flushRun({required bool allowBlank}) {
      if (run == null) return;
      if (isBlankParagraphText(run!.text) && !allowBlank) {
        run = null;
        return;
      }
      blocks.add(run!);
      run = null;
    }

    for (final block in doc.blocks) {
      if (block is ParagraphNode) {
        if (run == null) {
          run = block;
        } else if (isBlankParagraphText(block.text)) {
          // Discard blank follower — no blank-line gap after a deleted embed.
          continue;
        } else if (isBlankParagraphText(run!.text)) {
          run = block;
        } else {
          final joinAt = run!.text.length + 1;
          run = ParagraphNode(
            id: run!.id,
            text: '${run!.text}\n${block.text}',
            spans: [
              ...run!.spans,
              for (final span in block.spans)
                span.copyWith(
                  start: span.start + joinAt,
                  end: span.end + joinAt,
                ),
            ],
          );
        }
      } else {
        // Do not keep a blank paragraph pressed against a non-paragraph.
        flushRun(allowBlank: false);
        blocks.add(block);
      }
    }
    // Trailing blank after an embed/list/table is dropped; a sole empty doc stays.
    flushRun(allowBlank: blocks.isEmpty);
    if (blocks.isEmpty) {
      blocks.add(ParagraphNode(id: newId('b'), text: ''));
    }
    return doc.copyWith(blocks: blocks);
  }

  static int? embedBlockIndex(RichDocument doc, int objectId) {
    for (var i = 0; i < doc.blocks.length; i++) {
      final block = doc.blocks[i];
      if (block is EmbedNode && block.objectId == objectId) return i;
    }
    return null;
  }
}
