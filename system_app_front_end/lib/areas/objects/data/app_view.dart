class AppView {
  const AppView({
    required this.id,
    required this.workspaceId,
    required this.name,
    this.layoutConfig = const {},
    this.orderIndex = 0,
    this.archivedAt,
  });

  final int id;
  final int workspaceId;
  final String name;
  final Map<String, dynamic> layoutConfig;
  final int orderIndex;
  final String? archivedAt;

  String get type => 'view_$id';

  factory AppView.fromJson(Map<String, dynamic> json) {
    final layout = json['layout_config'];
    return AppView(
      id: json['id'] as int,
      workspaceId: json['workspace_id'] as int,
      name: json['name'] as String,
      layoutConfig: layout is Map<String, dynamic>
          ? Map<String, dynamic>.from(layout)
          : const {},
      orderIndex: json['order_index'] as int? ?? 0,
      archivedAt: json['archived_at'] as String?,
    );
  }
}

class ViewMembership {
  const ViewMembership({
    required this.id,
    required this.viewId,
    this.taskId,
    this.sectionName,
    this.orderIndex = 0,
    this.sectionFlag,
    this.topicKey,
    this.task,
  });

  final int id;
  final int viewId;
  final int? taskId;
  final String? sectionName;
  final int orderIndex;
  final String? sectionFlag;
  final String? topicKey;
  final Map<String, dynamic>? task;

  factory ViewMembership.fromJson(Map<String, dynamic> json) {
    return ViewMembership(
      id: json['id'] as int,
      viewId: json['view_id'] as int,
      taskId: json['task_id'] as int?,
      sectionName: json['section_name'] as String?,
      orderIndex: json['order_index'] as int? ?? 0,
      sectionFlag: json['section_flag'] as String?,
      topicKey: json['topic_key'] as String?,
      task: json['task'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(json['task'] as Map)
          : null,
    );
  }

  ViewMembership copyWith({
    int? orderIndex,
    Map<String, dynamic>? task,
    String? sectionName,
    String? sectionFlag,
    String? topicKey,
  }) {
    return ViewMembership(
      id: id,
      viewId: viewId,
      taskId: taskId,
      sectionName: sectionName ?? this.sectionName,
      orderIndex: orderIndex ?? this.orderIndex,
      sectionFlag: sectionFlag ?? this.sectionFlag,
      topicKey: topicKey ?? this.topicKey,
      task: task ?? this.task,
    );
  }

  Map<String, dynamic> toReplaceJson() => {
        'task_id': taskId,
        'section_name': sectionName,
        'order_index': orderIndex,
        'section_flag': sectionFlag,
        'topic_key': topicKey,
      };
}
