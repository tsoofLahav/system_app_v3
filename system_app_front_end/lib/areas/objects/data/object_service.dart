import './object_embed.dart';
import '../../../core/models/tag.dart';
import '../../../core/services/api_service.dart';

enum DiagramColorMode { byTopic, byTag }

class ObjectGraphData {
  const ObjectGraphData({required this.nodes, required this.edges});

  final List<ObjectGraphNode> nodes;
  final List<ObjectGraphEdge> edges;

  factory ObjectGraphData.fromJson(Map<String, dynamic> json) {
    return ObjectGraphData(
      nodes: [
        for (final n in (json['nodes'] as List? ?? const []))
          ObjectGraphNode.fromJson(Map<String, dynamic>.from(n as Map)),
      ],
      edges: [
        for (final e in (json['edges'] as List? ?? const []))
          ObjectGraphEdge.fromJson(Map<String, dynamic>.from(e as Map)),
      ],
    );
  }
}

class ObjectGraphNode {
  const ObjectGraphNode({
    required this.objectId,
    required this.type,
    required this.title,
    required this.fileId,
    required this.tagIds,
    this.body = '',
    this.informationId,
    this.topicId,
    this.topicColor,
    this.diagramX,
    this.diagramY,
  });

  final int objectId;
  final String type;
  final String title;
  final String body;
  final int? informationId;
  final int fileId;
  final int? topicId;
  final String? topicColor;
  final List<int> tagIds;
  final double? diagramX;
  final double? diagramY;

  factory ObjectGraphNode.fromJson(Map<String, dynamic> json) {
    return ObjectGraphNode(
      objectId: json['object_id'] as int,
      type: json['type'] as String? ?? 'info',
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      informationId: json['information_id'] as int?,
      fileId: json['file_id'] as int? ?? 0,
      topicId: json['topic_id'] as int?,
      topicColor: json['topic_color'] as String?,
      tagIds: [
        for (final id in (json['tag_ids'] as List? ?? const [])) id as int,
      ],
      diagramX: _readCoord(json['diagram_x']),
      diagramY: _readCoord(json['diagram_y']),
    );
  }

  ObjectGraphNode copyWith({
    String? title,
    String? body,
    double? diagramX,
    double? diagramY,
  }) {
    return ObjectGraphNode(
      objectId: objectId,
      type: type,
      title: title ?? this.title,
      body: body ?? this.body,
      informationId: informationId,
      fileId: fileId,
      topicId: topicId,
      topicColor: topicColor,
      tagIds: tagIds,
      diagramX: diagramX ?? this.diagramX,
      diagramY: diagramY ?? this.diagramY,
    );
  }
}

double? _readCoord(Object? value) {
  if (value is num) return value.toDouble();
  return null;
}

class ObjectGraphEdge {
  const ObjectGraphEdge({
    required this.id,
    required this.kind,
    required this.sourceId,
    required this.targetId,
    this.label,
  });

  final int id;
  final String kind;
  final int sourceId;
  final int targetId;
  final String? label;

  factory ObjectGraphEdge.fromJson(Map<String, dynamic> json) {
    return ObjectGraphEdge(
      id: json['id'] as int,
      kind: json['kind'] as String? ?? 'related',
      sourceId: json['source_id'] as int,
      targetId: json['target_id'] as int,
      label: json['label'] as String?,
    );
  }
}

class ObjectService {
  ObjectService(this._api);

  final ApiService _api;

  Future<List<ObjectEmbed>> listForFile(int fileId) async {
    final data = await _api.get('/files/$fileId/objects') as List<dynamic>;
    return data
        .map((e) => ObjectEmbed.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<ObjectEmbed> getObject(int objectId) async {
    final data =
        await _api.get('/objects/$objectId') as Map<String, dynamic>;
    return ObjectEmbed.fromJson(data);
  }

  Future<ObjectEmbed> createObject({
    required int fileId,
    required String type,
    String? title,
    String? body,
    Map<String, dynamic>? metadata,
    Map<String, dynamic>? payload,
    int? blockIndex,
    int? index,
    int? offset,
  }) async {
    final data =
        await _api.post('/files/$fileId/objects', {
              'type': type,
              if (title != null) 'title': title,
              if (body != null) 'body': body,
              if (metadata != null) 'metadata': metadata,
              if (payload != null) 'payload': payload,
              if (blockIndex != null) 'block_index': blockIndex,
              if (index != null) 'index': index,
              if (offset != null) 'offset': offset,
            })
            as Map<String, dynamic>;
    return ObjectEmbed.fromJson(data);
  }

  Future<void> deleteEmbed(int objectId) async {
    await _api.delete('/objects/$objectId');
  }

  Future<ObjectGraphData> loadGraph({required int workspaceId}) async {
    final data = await _api.get('/objects/graph?workspace_id=$workspaceId')
        as Map<String, dynamic>;
    return ObjectGraphData.fromJson(data);
  }

  Future<void> saveDiagramPositions({
    required int workspaceId,
    required List<({int objectId, double x, double y})> positions,
  }) async {
    if (positions.isEmpty) return;
    await _api.put('/objects/graph/positions', {
      'workspace_id': workspaceId,
      'positions': [
        for (final p in positions)
          {'object_id': p.objectId, 'x': p.x, 'y': p.y},
      ],
    });
  }

  Future<List<Map<String, dynamic>>> listLinks(int objectId) async {
    return (await _api.get('/objects/$objectId/links') as List<dynamic>)
        .cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> listFileDescriptionLinks(int fileId) async {
    return (await _api.get('/files/$fileId/description-links') as List<dynamic>)
        .cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> createRelatedLink(
    int objectId, {
    required int targetObjectId,
    String? label,
  }) async {
    return await _api.post('/objects/$objectId/links', {
          'kind': 'related',
          'target_object_id': targetObjectId,
          if (label != null) 'label': label,
        })
        as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createDescriptionLink(
    int objectId, {
    required Map<String, dynamic> anchor,
    String? label,
  }) async {
    return await _api.post('/objects/$objectId/links', {
          'kind': 'description',
          'anchor': anchor,
          if (label != null) 'label': label,
        })
        as Map<String, dynamic>;
  }

  Future<void> deleteLink(int objectId, int linkId) async {
    await _api.delete('/objects/$objectId/links/$linkId');
  }

  Future<List<AppTag>> replaceObjectTags(
    int objectId,
    List<int> tagIds,
  ) async {
    final data = await _api.put('/objects/$objectId/tags', {
      'tag_ids': tagIds,
    }) as List<dynamic>;
    return data.map((e) => AppTag.fromJson(e as Map<String, dynamic>)).toList();
  }
}
