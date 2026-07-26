import 'dart:convert';
import 'dart:math';

import 'document_model.dart';

class DocumentCodec {
  static const version = 1;

  static String newNodeId() =>
      'n${Random().nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  static RichDocument empty() => const RichDocument(version: version, nodes: []);

  static RichDocument parse(String? body) {
    final raw = body?.trim() ?? '';
    if (raw.isEmpty) return empty();
    try {
      final data = jsonDecode(raw);
      if (data is Map<String, dynamic> && data['nodes'] is List) {
        return RichDocument(
          version: data['version'] as int? ?? version,
          nodes: [
            for (final item in data['nodes'] as List)
              if (item is Map<String, dynamic>) _nodeFromJson(item),
          ],
        );
      }
    } catch (_) {}
    return _migratePlainBody(body ?? '');
  }

  static String serialize(RichDocument doc) =>
      jsonEncode(doc.toJson());

  static String plainText(String? body) {
    final doc = parse(body);
    final lines = <String>[];
    for (final node in doc.nodes) {
      switch (node) {
        case ParagraphNode(:final text):
          if (text.isNotEmpty) lines.add(text);
        case TableNode(:final rows):
          for (final row in rows) {
            lines.add(row.join(' | '));
          }
        case ListNode(:final items, :final listStyle):
          for (var i = 0; i < items.length; i++) {
            final prefix = listStyle == 'numbered' ? '${i + 1}.' : '•';
            lines.add('$prefix ${items[i]}');
          }
        case ImageNode(:final url):
          lines.add('[image: $url]');
        case GraphNode():
          lines.add('[graph]');
        case ObjectNode(:final objectType, :final objectId):
          lines.add('[$objectType #$objectId]');
      }
    }
    return lines.join('\n');
  }

  static DocumentNode _nodeFromJson(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? newNodeId();
    switch (json['type']) {
      case 'paragraph':
        final spansRaw = json['spans'];
        return ParagraphNode(
          id: id,
          text: json['text'] as String? ?? '',
          spans: spansRaw is List
              ? [
                  for (final s in spansRaw)
                    if (s is Map<String, dynamic>) TextSpanMark.fromJson(s),
                ]
              : const [],
        );
      case 'table':
        return TableNode(
          id: id,
          rows: _rowsFromJson(json['rows']),
        );
      case 'list':
        return ListNode(
          id: id,
          items: _stringList(json['items']),
          listStyle: json['list_style'] as String? ?? 'bullet',
        );
      case 'image':
        return ImageNode(
          id: id,
          url: json['url'] as String? ?? '',
          width: (json['width'] as num?)?.toDouble(),
        );
      case 'graph':
        return GraphNode(
          id: id,
          labels: _stringList(json['labels']),
          values: [
            for (final v in (json['values'] as List? ?? const []))
              (v as num).toDouble(),
          ],
        );
      case 'object':
        return ObjectNode(
          id: id,
          objectType: json['object_type'] as String,
          objectId: json['object_id'] as int,
        );
      default:
        return ParagraphNode(id: id, text: '');
    }
  }

  static RichDocument _migratePlainBody(String body) {
    final nodes = <DocumentNode>[];
    final taskMarker = RegExp(r'^\{\{task:(\d+)\}\}$');
    final infoMarker = RegExp(r'^\{\{info:(\d+)\}\}$');
    for (final line in body.split('\n')) {
      final trimmed = line.trim();
      final taskMatch = taskMarker.firstMatch(trimmed);
      if (taskMatch != null) {
        nodes.add(
          ObjectNode(
            id: newNodeId(),
            objectType: 'task_list',
            objectId: int.parse(taskMatch.group(1)!),
          ),
        );
        continue;
      }
      final infoMatch = infoMarker.firstMatch(trimmed);
      if (infoMatch != null) {
        nodes.add(
          ObjectNode(
            id: newNodeId(),
            objectType: 'info',
            objectId: int.parse(infoMatch.group(1)!),
          ),
        );
        continue;
      }
      if (line.isNotEmpty || nodes.isNotEmpty) {
        nodes.add(ParagraphNode(id: newNodeId(), text: line));
      }
    }
    if (nodes.isEmpty) {
      nodes.add(ParagraphNode(id: newNodeId(), text: ''));
    }
    return RichDocument(version: version, nodes: nodes);
  }

  static List<List<String>> _rowsFromJson(Object? value) {
    if (value is! List || value.isEmpty) return [['', '']];
    return [
      for (final row in value)
        if (row is List)
          [
            for (final cell in row) cell?.toString() ?? '',
          ]
        else
          [''],
    ];
  }

  static List<String> _stringList(Object? value) {
    if (value is! List || value.isEmpty) return [''];
    return [for (final item in value) item?.toString() ?? ''];
  }
}
