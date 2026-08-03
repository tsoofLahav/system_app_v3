import '../models/tag.dart';
import './api_service.dart';

class TagService {
  TagService(this._api);

  final ApiService _api;

  Future<List<AppTag>> listTags({int? workspaceId}) async {
    final path = workspaceId != null
        ? '/tags?workspace_id=$workspaceId'
        : '/tags';
    final data = await _api.get(path) as List<dynamic>;
    return data.map((e) => AppTag.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<AppTag> createTag({
    required int workspaceId,
    required String name,
    String? color,
    String? icon,
  }) async {
    final data = await _api.post('/tags', {
      'workspace_id': workspaceId,
      'name': name,
      if (color != null) 'color': color,
      if (icon != null) 'icon': icon,
    }) as Map<String, dynamic>;
    return AppTag.fromJson(data);
  }

  Future<AppTag> updateTag(
    int tagId, {
    String? name,
    String? color,
    String? icon,
  }) async {
    final data = await _api.patch('/tags/$tagId', {
      if (name != null) 'name': name,
      if (color != null) 'color': color,
      if (icon != null) 'icon': icon,
    }) as Map<String, dynamic>;
    return AppTag.fromJson(data);
  }

  Future<void> deleteTag(int tagId) async {
    await _api.delete('/tags/$tagId');
  }

  Future<void> assignTag({
    required int tagId,
    required String entityType,
    required int entityId,
  }) async {
    await _api.post('/tags/assign', {
      'tag_id': tagId,
      'entity_type': entityType,
      'entity_id': entityId,
    });
  }

  Future<void> unassignTag({
    required int tagId,
    required String entityType,
    required int entityId,
  }) async {
    await _api.delete('/tags/assign', body: {
      'tag_id': tagId,
      'entity_type': entityType,
      'entity_id': entityId,
    });
  }
}
