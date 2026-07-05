import '../models/task_reset_acknowledgement.dart';
import 'api_service.dart';

class TaskResetAcknowledgementService {
  TaskResetAcknowledgementService(this._api);

  final ApiService _api;

  Future<List<TaskResetAcknowledgement>> listPendingForView(
    String viewType,
  ) async {
    final data = await _api.get(
      '/task_reset_acknowledgements?view_type=$viewType&status=pending&limit=5',
    ) as List<dynamic>;
    return data
        .map(
          (item) => TaskResetAcknowledgement.fromJson(
            item as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  Future<TaskResetAcknowledgement> approve(int id) async {
    final data = await _api.post(
      '/task_reset_acknowledgements/$id/approve',
      {},
    ) as Map<String, dynamic>;
    return TaskResetAcknowledgement.fromJson(data);
  }
}
