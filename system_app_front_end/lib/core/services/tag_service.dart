import '../models/tag.dart';
import 'api_service.dart';

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
}
