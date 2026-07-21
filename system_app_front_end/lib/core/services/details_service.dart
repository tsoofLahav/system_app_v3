import '../models/details_block_summary.dart';
import 'api_service.dart';

class DetailsService {
  DetailsService(this._api);

  final ApiService _api;

  Future<List<DetailsBlockSummary>> listForTopic(int topicId) async {
    final data =
        await _api.get('/topics/$topicId/details-blocks') as List<dynamic>;
    return data
        .map(
          (entry) =>
              DetailsBlockSummary.fromJson(entry as Map<String, dynamic>),
        )
        .toList();
  }
}
