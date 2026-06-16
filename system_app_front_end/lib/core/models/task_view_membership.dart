class TaskViewMembership {
  const TaskViewMembership({
    required this.id,
    required this.taskId,
    required this.viewType,
    this.sectionName,
  });

  final int id;
  final int taskId;
  final String viewType;
  final String? sectionName;

  factory TaskViewMembership.fromJson(Map<String, dynamic> json) {
    return TaskViewMembership(
      id: json['id'] as int,
      taskId: json['task_id'] as int,
      viewType: json['view_type'] as String,
      sectionName: json['section_name'] as String?,
    );
  }
}
