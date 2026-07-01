class AutomationCompanionLink {
  const AutomationCompanionLink({
    required this.id,
    required this.taskId,
    required this.ruleKey,
    required this.flowKey,
    this.topicId,
    this.topicName,
    this.topicColor,
    this.topicIcon,
    this.topicType,
    this.payload = const {},
  });

  final int id;
  final int taskId;
  final String ruleKey;
  final String flowKey;
  final int? topicId;
  final String? topicName;
  final String? topicColor;
  final String? topicIcon;
  final String? topicType;
  final Map<String, dynamic> payload;

  bool get isProcess => topicType == null || topicType == 'process';

  int? get proposalId {
    final raw = payload['proposal_id'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return null;
  }

  String get displayTopicName {
    final name = topicName ?? payload['topic_name']?.toString();
    if (name == null || name.isEmpty) return 'Process';
    if (name == 'main') return 'Main';
    return name;
  }

  factory AutomationCompanionLink.fromJson(Map<String, dynamic> json) {
    final rawPayload = json['payload'];
    return AutomationCompanionLink(
      id: json['id'] as int,
      taskId: json['task_id'] as int,
      ruleKey: json['rule_key'] as String,
      flowKey: json['flow_key'] as String,
      topicId: json['topic_id'] as int?,
      topicName: json['topic_name'] as String?,
      topicColor: json['topic_color'] as String?,
      topicIcon: json['topic_icon'] as String?,
      topicType: json['topic_type'] as String?,
      payload: rawPayload is Map<String, dynamic>
          ? Map<String, dynamic>.from(rawPayload)
          : const {},
    );
  }
}
