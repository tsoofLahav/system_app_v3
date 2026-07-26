import 'dart:convert';
import 'dart:math';

import 'inline_document_model.dart';

class DocumentCodec {
  static String newId([String prefix = 'e']) =>
      '$prefix${Random().nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  static InlineDocument empty() => const InlineDocument(
    version: InlineDocument.documentVersion,
    text: '',
  );

  static InlineDocument parse(String? body) {
    final raw = body?.trim() ?? '';
    if (raw.isEmpty) return empty();
    try {
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic>) return _migratePlain(raw);
      final version = data['version'] as int? ?? 1;
      if (version >= 2 && data.containsKey('text')) {
        return _fromV2(data);
      }
      if (data['nodes'] is List) {
        return _migrateV1Nodes(data['nodes'] as List);
      }
    } catch (_) {}
    return _migratePlain(raw);
  }

  static String serialize(InlineDocument doc) =>
      jsonEncode(doc.toJson());

  static String plainText(String? body) {
    final doc = parse(body);
    final buffer = StringBuffer(doc.text.replaceAll(InlineDocument.embedChar, ' '));
    for (final embed in doc.embeds) {
      buffer.writeln();
      switch (embed.kind) {
        case 'object':
          buffer.write('[${embed.objectType} #${embed.objectId}]');
        case 'image':
          buffer.write('[image: ${embed.url}]');
        case 'graph':
          buffer.write('[graph]');
      }
    }
    return buffer.toString().trim();
  }

  static InlineDocument _fromV2(Map<String, dynamic> data) {
    final spansRaw = data['spans'];
    final regionsRaw = data['regions'];
    final embedsRaw = data['embeds'];
    return InlineDocument(
      version: InlineDocument.documentVersion,
      text: data['text'] as String? ?? '',
      spans: spansRaw is List
          ? [
              for (final s in spansRaw)
                if (s is Map<String, dynamic>) TextSpanMark.fromJson(s),
            ]
          : const [],
      regions: regionsRaw is List
          ? [
              for (final r in regionsRaw)
                if (r is Map<String, dynamic>) DocumentRegion.fromJson(r),
            ]
          : const [],
      embeds: embedsRaw is List
          ? [
              for (final e in embedsRaw)
                if (e is Map<String, dynamic>) DocumentEmbed.fromJson(e),
            ]
          : const [],
    );
  }

  static InlineDocument _migrateV1Nodes(List nodes) {
    final buffer = StringBuffer();
    final spans = <TextSpanMark>[];
    final regions = <DocumentRegion>[];
    final embeds = <DocumentEmbed>[];
    var cursor = 0;

    void append(String s) {
      buffer.write(s);
      cursor += s.length;
    }

    for (final raw in nodes) {
      if (raw is! Map<String, dynamic>) continue;
      switch (raw['type']) {
        case 'paragraph':
          if (buffer.isNotEmpty) append('\n');
          final block = raw['text'] as String? ?? '';
          final start = cursor;
          append(block);
          final spansRaw = raw['spans'];
          if (spansRaw is List) {
            for (final s in spansRaw) {
              if (s is Map<String, dynamic>) {
                spans.add(
                  TextSpanMark.fromJson(s).shift(start),
                );
              }
            }
          }
        case 'list':
          if (buffer.isNotEmpty) append('\n');
          final items = raw['items'] is List ? raw['items'] as List : [''];
          final listStyle = raw['list_style'] as String? ?? 'bullet';
          final lines = <String>[];
          for (var i = 0; i < items.length; i++) {
            final prefix = listStyle == 'numbered' ? '${i + 1}. ' : '• ';
            lines.add('$prefix${items[i]}');
          }
          final start = cursor;
          append(lines.join('\n'));
          regions.add(
            DocumentRegion(
              id: newId('r'),
              kind: 'list',
              start: start,
              end: cursor,
              listStyle: listStyle,
            ),
          );
        case 'table':
          if (buffer.isNotEmpty) append('\n');
          final rows = raw['rows'] is List ? raw['rows'] as List : [['', '']];
          final start = cursor;
          append(
            rows
                .map((r) => r is List ? r.map((c) => c.toString()).join('\t') : '')
                .join('\n'),
          );
          regions.add(
            DocumentRegion(
              id: newId('r'),
              kind: 'table',
              start: start,
              end: cursor,
              rows: [
                for (final r in rows)
                  if (r is List) [for (final c in r) c.toString()] else [''],
              ],
            ),
          );
        case 'image':
          if (buffer.isNotEmpty) append('\n');
          embeds.add(
            DocumentEmbed(
              id: newId('e'),
              kind: 'image',
              offset: cursor,
              url: raw['url'] as String? ?? '',
              width: (raw['width'] as num?)?.toDouble(),
            ),
          );
          append(InlineDocument.embedChar);
        case 'graph':
          if (buffer.isNotEmpty) append('\n');
          embeds.add(
            DocumentEmbed(
              id: newId('e'),
              kind: 'graph',
              offset: cursor,
              labels: raw['labels'] is List
                  ? [for (final l in raw['labels'] as List) l.toString()]
                  : const [],
              values: raw['values'] is List
                  ? [for (final v in raw['values'] as List) (v as num).toDouble()]
                  : const [],
            ),
          );
          append(InlineDocument.embedChar);
        case 'object':
          if (buffer.isNotEmpty) append('\n');
          embeds.add(
            DocumentEmbed(
              id: newId('e'),
              kind: 'object',
              offset: cursor,
              objectType: raw['object_type'] as String?,
              objectId: raw['object_id'] as int?,
            ),
          );
          append(InlineDocument.embedChar);
      }
    }
    return InlineDocument(
      version: InlineDocument.documentVersion,
      text: buffer.toString(),
      spans: spans,
      regions: regions,
      embeds: embeds,
    );
  }

  static InlineDocument _migratePlain(String body) {
    final nodes = <Map<String, dynamic>>[];
    for (final line in body.split('\n')) {
      final stripped = line.trim();
      final taskMatch = RegExp(r'^\{\{task:(\d+)\}\}$').firstMatch(stripped);
      if (taskMatch != null) {
        nodes.add({
          'type': 'object',
          'object_type': 'task_list',
          'object_id': int.parse(taskMatch.group(1)!),
        });
        continue;
      }
      final infoMatch = RegExp(r'^\{\{info:(\d+)\}\}$').firstMatch(stripped);
      if (infoMatch != null) {
        nodes.add({
          'type': 'object',
          'object_type': 'info',
          'object_id': int.parse(infoMatch.group(1)!),
        });
        continue;
      }
      if (line.isNotEmpty || nodes.isNotEmpty) {
        nodes.add({'type': 'paragraph', 'text': line, 'spans': []});
      }
    }
    if (nodes.isEmpty) {
      nodes.add({'type': 'paragraph', 'text': '', 'spans': []});
    }
    return _migrateV1Nodes(nodes);
  }

  static InlineDocument insertEmbed(
    InlineDocument doc,
    DocumentEmbed embed, {
    int? offset,
  }) {
    final pos = offset ?? doc.text.length;
    final clamped = pos.clamp(0, doc.text.length);
    final text =
        doc.text.substring(0, clamped) +
        InlineDocument.embedChar +
        doc.text.substring(clamped);
    final embeds = [
      for (final e in doc.embeds)
        e.copyWith(offset: e.offset >= clamped ? e.offset + 1 : e.offset),
      embed.copyWith(offset: clamped),
    ];
    final regions = [
      for (final r in doc.regions)
        r.copyWith(
          start: r.start >= clamped ? r.start + 1 : r.start,
          end: r.end >= clamped ? r.end + 1 : r.end,
        ),
    ];
    final spans = [
      for (final s in doc.spans)
        TextSpanMark(
          start: s.start >= clamped ? s.start + 1 : s.start,
          end: s.end >= clamped ? s.end + 1 : s.end,
          bold: s.bold,
          italic: s.italic,
          underline: s.underline,
          size: s.size,
        ),
    ];
    return doc.copyWith(
      text: text,
      embeds: embeds,
      regions: regions,
      spans: spans,
    );
  }

  static InlineDocument moveEmbed(InlineDocument doc, String embedId, int newOffset) {
    final embed = doc.embeds.where((e) => e.id == embedId).firstOrNull;
    if (embed == null) return doc;
    var working = removeEmbed(doc, embedId);
    return insertEmbed(working, embed, offset: newOffset);
  }

  static InlineDocument removeEmbed(InlineDocument doc, String embedId) {
    final embed = doc.embeds.where((e) => e.id == embedId).firstOrNull;
    if (embed == null) return doc;
    final pos = embed.offset;
    final text = doc.text.substring(0, pos) + doc.text.substring(pos + 1);
    return doc.copyWith(
      text: text,
      embeds: [
        for (final e in doc.embeds)
          if (e.id != embedId)
            e.copyWith(offset: e.offset > pos ? e.offset - 1 : e.offset),
      ],
      regions: [
        for (final r in doc.regions)
          r.copyWith(
            start: r.start > pos ? r.start - 1 : r.start,
            end: r.end > pos ? r.end - 1 : r.end,
          ),
      ],
      spans: [
        for (final s in doc.spans)
          TextSpanMark(
            start: s.start > pos ? s.start - 1 : s.start,
            end: s.end > pos ? s.end - 1 : s.end,
            bold: s.bold,
            italic: s.italic,
            underline: s.underline,
            size: s.size,
          ),
      ],
    );
  }

  static InlineDocument replaceTextRange(
    InlineDocument doc,
    int start,
    int end,
    String replacement,
  ) {
    final s = start.clamp(0, doc.text.length);
    final e = end.clamp(s, doc.text.length);
    final delta = replacement.length - (e - s);
    final text = doc.text.substring(0, s) + replacement + doc.text.substring(e);
    return doc.copyWith(
      text: text,
      spans: [
        for (final span in doc.spans)
          if (span.end <= s)
            span
          else if (span.start >= e)
            TextSpanMark(
              start: span.start + delta,
              end: span.end + delta,
              bold: span.bold,
              italic: span.italic,
              underline: span.underline,
              size: span.size,
            ),
      ],
      regions: [
        for (final region in doc.regions)
          if (region.end <= s || region.start >= e)
            region.copyWith(
              start: region.start >= e ? region.start + delta : region.start,
              end: region.end >= e ? region.end + delta : region.end,
            )
          else if (region.start <= s && region.end >= e)
            region.copyWith(start: s, end: s + replacement.length)
          else if (region.start < s)
            region.copyWith(end: s)
          else if (region.end > e)
            region.copyWith(start: s + replacement.length, end: region.end + delta),
      ].where((r) => r.end > r.start).toList(),
      embeds: [
        for (final embed in doc.embeds)
          embed.copyWith(
            offset: embed.offset <= s
                ? embed.offset
                : embed.offset >= e
                    ? embed.offset + delta
                    : s,
          ),
      ],
    );
  }

  static InlineDocument insertRegion(
    InlineDocument doc,
    DocumentRegion region, {
    int? offset,
  }) {
    final pos = (offset ?? doc.text.length).clamp(0, doc.text.length);
    final seed = region.kind == 'list'
        ? (region.listStyle == 'numbered' ? '1. \n' : '• \n')
        : '\t\n\t';
    final text =
        doc.text.substring(0, pos) + seed + doc.text.substring(pos);
    final delta = seed.length;
    return doc.copyWith(
      text: text,
      regions: [
        ...doc.regions.map(
          (r) => r.copyWith(
            start: r.start >= pos ? r.start + delta : r.start,
            end: r.end >= pos ? r.end + delta : r.end,
          ),
        ),
        region.copyWith(start: pos, end: pos + delta),
      ],
      embeds: [
        for (final e in doc.embeds)
          e.copyWith(offset: e.offset >= pos ? e.offset + delta : e.offset),
      ],
      spans: [
        for (final s in doc.spans)
          TextSpanMark(
            start: s.start >= pos ? s.start + delta : s.start,
            end: s.end >= pos ? s.end + delta : s.end,
            bold: s.bold,
            italic: s.italic,
            underline: s.underline,
            size: s.size,
          ),
      ],
    );
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    if (!it.moveNext()) return null;
    return it.current;
  }
}
