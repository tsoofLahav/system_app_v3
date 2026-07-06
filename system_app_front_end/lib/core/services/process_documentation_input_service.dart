import 'api_service.dart';

class ProcessDocumentationInputService {
  ProcessDocumentationInputService(this._api);

  final ApiService _api;

  Future<Map<String, dynamic>> submit({
    required int topicId,
    required String text,
    required int grade,
    String? date,
    String? timezone,
  }) async {
    final data = await _api.post('/process_documentation_inputs', {
      'topic_id': topicId,
      'text': text,
      'grade': grade,
      if (date != null) 'date': date,
      if (timezone != null) 'timezone': timezone,
    });
    return Map<String, dynamic>.from(data as Map);
  }
}
