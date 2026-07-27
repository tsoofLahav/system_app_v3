class TaskResetAcknowledgement {
  const TaskResetAcknowledgement({
    required this.id,
    required this.viewType,
    required this.payload,
    required this.status,
    this.automationRunId,
    this.ruleId,
    this.reportFileId,
    this.createdAt,
    this.approvedAt,
  });

  final int id;
  final int? automationRunId;
  final int? ruleId;
  final String viewType;
  final int? reportFileId;
  final Map<String, dynamic> payload;
  final String status;
  final String? createdAt;
  final String? approvedAt;

  int get resetCount => payload['reset_count'] as int? ?? 0;
  int get missedCount => payload['missed_count'] as int? ?? 0;
  String? get resetAt => payload['reset_at'] as String?;

  List<Map<String, dynamic>> get missedTasks =>
      _taskList(payload['missed_tasks']);

  List<Map<String, dynamic>> get resetTasks =>
      _taskList(payload['reset_tasks']);

  static List<Map<String, dynamic>> _taskList(Object? value) {
    if (value is! List) return const [];
    return [
      for (final item in value)
        if (item is Map<String, dynamic>) Map<String, dynamic>.from(item),
    ];
  }

  factory TaskResetAcknowledgement.fromJson(Map<String, dynamic> json) {
    final rawPayload = json['payload'];
    return TaskResetAcknowledgement(
      id: json['id'] as int,
      automationRunId: json['automation_run_id'] as int?,
      ruleId: json['rule_id'] as int?,
      viewType: json['view_type'] as String,
      reportFileId: json['report_file_id'] as int?,
      payload: rawPayload is Map<String, dynamic>
          ? Map<String, dynamic>.from(rawPayload)
          : const {},
      status: json['status'] as String? ?? 'pending',
      createdAt: json['created_at'] as String?,
      approvedAt: json['approved_at'] as String?,
    );
  }
}
