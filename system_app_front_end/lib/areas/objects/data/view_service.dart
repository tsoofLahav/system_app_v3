import './app_view.dart';
import '../../../core/services/api_service.dart';

class ViewService {
  ViewService(this._api);

  final ApiService _api;

  Future<List<AppView>> listViews({int? workspaceId}) async {
    final path = workspaceId != null
        ? '/views?workspace_id=$workspaceId'
        : '/views';
    final data = await _api.get(path) as List<dynamic>;
    return data.map((e) => AppView.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<AppView> createView({
    required int workspaceId,
    required String name,
    Map<String, dynamic>? layoutConfig,
  }) async {
    final data =
        await _api.post('/views', {
              'workspace_id': workspaceId,
              'name': name,
              if (layoutConfig != null) 'layout_config': layoutConfig,
            })
            as Map<String, dynamic>;
    return AppView.fromJson(data);
  }

  Future<List<ViewMembership>> listMemberships(int viewId) async {
    final data =
        await _api.get('/views/$viewId/memberships') as List<dynamic>;
    return data
        .map((e) => ViewMembership.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<ViewMembership>> replaceMemberships(
    int viewId,
    List<Map<String, dynamic>> memberships,
  ) async {
    final data =
        await _api.put('/views/$viewId/memberships', {
              'memberships': memberships,
            })
            as List<dynamic>;
    return data
        .map((e) => ViewMembership.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
