import '../models/ai_proposal.dart';
import 'api_service.dart';

class AiProposalService {
  AiProposalService(this._api);

  final ApiService _api;

  Future<AiProposal> getById(int id) async {
    final data =
        await _api.get('/ai_proposals/$id') as Map<String, dynamic>;
    return AiProposal.fromJson(data);
  }

  Future<List<AiProposal>> listPending({int? topicId}) async {
    final query = topicId == null ? '' : '&topic_id=$topicId';
    final data =
        await _api.get('/ai_proposals?status=pending$query') as List<dynamic>;
    return data
        .map((e) => AiProposal.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<AiProposal> approve(int id) async {
    final data =
        await _api.post('/ai_proposals/$id/approve', {})
            as Map<String, dynamic>;
    return AiProposal.fromJson(data);
  }

  Future<AiProposal> reject(int id) async {
    final data =
        await _api.post('/ai_proposals/$id/reject', {}) as Map<String, dynamic>;
    return AiProposal.fromJson(data);
  }

  Future<AiProposal> finalize(int id, Map<String, dynamic> decisions) async {
    final data =
        await _api.post('/ai_proposals/$id/finalize', {'decisions': decisions})
            as Map<String, dynamic>;
    return AiProposal.fromJson(data);
  }
}
