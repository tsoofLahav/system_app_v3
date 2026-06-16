class Task {
  const Task({
    required this.id,
    required this.blockId,
    required this.title,
    required this.status,
    this.dueDate,
    this.createdAt,
    this.taskViewId,
    this.viewType,
    this.sectionName,
    this.topicId,
    this.topicName,
  });

  final int id;
  final int? blockId;
  final String title;
  final String status;
  final String? dueDate;
  final String? createdAt;
  final int? taskViewId;
  final String? viewType;
  final String? sectionName;
  final int? topicId;
  final String? topicName;

  bool get isDone => status == 'done';

  String get displayTopicName {
    if (topicName == null || topicName == 'main') return 'Main';
    return topicName!;
  }

  Task copyWith({
    int? id,
    int? blockId,
    String? title,
    String? status,
    String? dueDate,
    String? createdAt,
    int? taskViewId,
    String? viewType,
    String? sectionName,
    int? topicId,
    String? topicName,
    bool clearSection = false,
  }) {
    return Task(
      id: id ?? this.id,
      blockId: blockId ?? this.blockId,
      title: title ?? this.title,
      status: status ?? this.status,
      dueDate: dueDate ?? this.dueDate,
      createdAt: createdAt ?? this.createdAt,
      taskViewId: taskViewId ?? this.taskViewId,
      viewType: viewType ?? this.viewType,
      sectionName: clearSection ? null : (sectionName ?? this.sectionName),
      topicId: topicId ?? this.topicId,
      topicName: topicName ?? this.topicName,
    );
  }

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: json['id'] as int,
      blockId: json['block_id'] as int?,
      title: json['title'] as String,
      status: json['status'] as String? ?? 'active',
      dueDate: json['due_date'] as String?,
      createdAt: json['created_at'] as String?,
      taskViewId: json['task_view_id'] as int?,
      viewType: json['view_type'] as String?,
      sectionName: json['section_name'] as String?,
      topicId: json['topic_id'] as int?,
      topicName: json['topic_name'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        if (blockId != null) 'block_id': blockId,
        'title': title,
        'status': status,
        if (dueDate != null) 'due_date': dueDate,
      };
}
