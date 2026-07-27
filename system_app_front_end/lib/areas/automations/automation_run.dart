class AutomationRun {
  const AutomationRun({
    required this.id,
    required this.ruleId,
    required this.status,
    required this.triggerSource,
    required this.eventContext,
    required this.result,
    this.startedAt,
    this.finishedAt,
    this.error,
  });

  final int id;
  final int ruleId;
  final String status;
  final String triggerSource;
  final Map<String, dynamic> eventContext;
  final Map<String, dynamic> result;
  final String? startedAt;
  final String? finishedAt;
  final String? error;

  bool get isActive => status == 'queued' || status == 'running';

  factory AutomationRun.fromJson(Map<String, dynamic> json) {
    final rawEventContext = json['event_context'];
    final rawResult = json['result'];
    return AutomationRun(
      id: json['id'] as int,
      ruleId: json['rule_id'] as int,
      status: json['status'] as String,
      triggerSource: json['trigger_source'] as String? ?? 'schedule',
      eventContext: rawEventContext is Map<String, dynamic>
          ? Map<String, dynamic>.from(rawEventContext)
          : <String, dynamic>{},
      result: rawResult is Map<String, dynamic>
          ? Map<String, dynamic>.from(rawResult)
          : <String, dynamic>{},
      startedAt: json['started_at'] as String?,
      finishedAt: json['finished_at'] as String?,
      error: json['error'] as String?,
    );
  }
}
