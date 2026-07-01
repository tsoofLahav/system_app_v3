import 'view_section_flags.dart';
import 'view_pane_sync_context.dart';

class Task {
  const Task({
    required this.id,
    required this.blockId,
    required this.title,
    required this.status,
    this.dueDate,
    this.archivedAt,
    this.createdAt,
    this.taskViewId,
    this.viewType,
    this.sectionName,
    this.sectionFlag,
    this.topicId,
    this.topicName,
    this.topicKey,
    this.subjectTopicName,
    this.companionTaskId,
    this.flowKey,
    this.companionPayload = const {},
    this.automationRuleKey,
    this.isAutomationTrigger = false,
    this.pendingCompanionCount = 0,
    this.hasPendingCompanionFlow = false,
  });

  final int id;
  final int? blockId;
  final String title;
  final String status;
  final String? dueDate;
  final String? archivedAt;
  final String? createdAt;
  final int? taskViewId;
  final String? viewType;
  final String? sectionName;
  final String? sectionFlag;
  final int? topicId;
  final String? topicName;
  final String? topicKey;
  final String? subjectTopicName;
  final int? companionTaskId;
  final String? flowKey;
  final Map<String, dynamic> companionPayload;
  final String? automationRuleKey;
  final bool isAutomationTrigger;
  final int pendingCompanionCount;
  final bool hasPendingCompanionFlow;

  bool get isDone => status == 'done';

  bool get isCompanionTask =>
      hasPendingCompanionFlow || companionTaskId != null || flowKey != null;

  bool get isAutomationsTopic =>
      topicKey == ViewPaneKeys.automations ||
      topicName == ViewPaneKeys.automations;

  bool get hasAutomationFlow => hasPendingCompanionFlow;

  bool get isImportant => sectionFlagIsImportant(sectionFlag);

  String get displayTopicName {
    if (topicName == null || topicName == 'main') return 'Main';
    return topicName!;
  }

  String? get displaySubjectTopicName {
    final name = subjectTopicName ??
        companionPayload['topic_name']?.toString();
    if (name == null || name.isEmpty || name == 'main') {
      return name == 'main' ? 'Main' : name;
    }
    return name;
  }

  Task copyWith({
    int? id,
    int? blockId,
    String? title,
    String? status,
    String? dueDate,
    String? archivedAt,
    String? createdAt,
    int? taskViewId,
    String? viewType,
    String? sectionName,
    String? sectionFlag,
    int? topicId,
    String? topicName,
    String? topicKey,
    String? subjectTopicName,
    int? companionTaskId,
    String? flowKey,
    Map<String, dynamic>? companionPayload,
    String? automationRuleKey,
    bool? isAutomationTrigger,
    int? pendingCompanionCount,
    bool? hasPendingCompanionFlow,
    bool clearSection = false,
    bool clearSectionFlag = false,
  }) {
    return Task(
      id: id ?? this.id,
      blockId: blockId ?? this.blockId,
      title: title ?? this.title,
      status: status ?? this.status,
      dueDate: dueDate ?? this.dueDate,
      archivedAt: archivedAt ?? this.archivedAt,
      createdAt: createdAt ?? this.createdAt,
      taskViewId: taskViewId ?? this.taskViewId,
      viewType: viewType ?? this.viewType,
      sectionName: clearSection ? null : (sectionName ?? this.sectionName),
      sectionFlag:
          clearSectionFlag ? null : (sectionFlag ?? this.sectionFlag),
      topicId: topicId ?? this.topicId,
      topicName: topicName ?? this.topicName,
      topicKey: topicKey ?? this.topicKey,
      subjectTopicName: subjectTopicName ?? this.subjectTopicName,
      companionTaskId: companionTaskId ?? this.companionTaskId,
      flowKey: flowKey ?? this.flowKey,
      companionPayload: companionPayload ?? this.companionPayload,
      automationRuleKey: automationRuleKey ?? this.automationRuleKey,
      isAutomationTrigger: isAutomationTrigger ?? this.isAutomationTrigger,
      pendingCompanionCount:
          pendingCompanionCount ?? this.pendingCompanionCount,
      hasPendingCompanionFlow:
          hasPendingCompanionFlow ?? this.hasPendingCompanionFlow,
    );
  }

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: json['id'] as int,
      blockId: json['block_id'] as int?,
      title: json['title'] as String,
      status: json['status'] as String? ?? 'active',
      dueDate: json['due_date'] as String?,
      archivedAt: json['archived_at'] as String?,
      createdAt: json['created_at'] as String?,
      taskViewId: json['task_view_id'] as int?,
      viewType: json['view_type'] as String?,
      sectionName: json['section_name'] as String?,
      sectionFlag: json['section_flag'] as String?,
      topicId: json['topic_id'] as int?,
      topicName: json['topic_name'] as String?,
      topicKey: json['topic_key'] as String?,
      subjectTopicName: json['subject_topic_name'] as String?,
      companionTaskId: json['companion_task_id'] as int?,
      flowKey: json['flow_key'] as String?,
      companionPayload: json['companion_payload'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(
              json['companion_payload'] as Map<String, dynamic>,
            )
          : const {},
      automationRuleKey: json['automation_rule_key'] as String?,
      isAutomationTrigger: json['is_automation_trigger'] as bool? ?? false,
      pendingCompanionCount: json['pending_companion_count'] as int? ?? 0,
      hasPendingCompanionFlow:
          json['has_pending_companion_flow'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    if (blockId != null) 'block_id': blockId,
    'title': title,
    'status': status,
    if (dueDate != null) 'due_date': dueDate,
    if (archivedAt != null) 'archived_at': archivedAt,
  };
}
