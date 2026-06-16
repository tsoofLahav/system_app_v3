import '../ai/ai_context.dart';
import 'api_service.dart';

class AiRunResult {
  AiRunResult({
    required this.tool,
    required this.action,
    this.result,
    this.targetFileId,
    this.targetFileName,
    this.targetTopicId,
    this.targetTopicName,
    this.blockId,
    this.imagePath,
    this.status,
  });

  final String tool;
  final String action;
  final String? result;
  final int? targetFileId;
  final String? targetFileName;
  final int? targetTopicId;
  final String? targetTopicName;
  final int? blockId;
  final String? imagePath;
  final String? status;

  factory AiRunResult.fromJson(Map<String, dynamic> json) {
    return AiRunResult(
      tool: json['tool'] as String? ?? '',
      action: json['action'] as String? ?? '',
      result: json['result']?.toString(),
      targetFileId: json['target_file_id'] as int?,
      targetFileName: json['target_file_name'] as String?,
      targetTopicId: json['target_topic_id'] as int?,
      targetTopicName: json['target_topic_name'] as String?,
      blockId: json['block_id'] as int?,
      imagePath: json['image_path'] as String?,
      status: json['status'] as String?,
    );
  }
}

class AiService {
  AiService(this._api);

  final ApiService _api;

  Future<AiRunResult> runTool({
    required String tool,
    required int topicId,
    required ResolvedAiContext context,
    required String locale,
  }) async {
    final data = await _api.post('/ai/run', {
      'tool': tool,
      'topic_id': topicId,
      'context': context.toJson(),
      'locale': locale,
    }) as Map<String, dynamic>;
    return AiRunResult.fromJson(data);
  }
}
