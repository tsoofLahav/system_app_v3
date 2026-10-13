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
          : layout is Map
              ? Map<String, dynamic>.from(layout)
              : const {},
      orderIndex: json['order_index'] as int? ?? 0,
      archivedAt: json['archived_at'] as String?,
    );
  }

  AppView copyWith({
    String? name,
    Map<String, dynamic>? layoutConfig,
    int? orderIndex,
    String? archivedAt,
  }) {
    return AppView(
      id: id,
      workspaceId: workspaceId,
      name: name ?? this.name,
      layoutConfig: layoutConfig ?? this.layoutConfig,
      orderIndex: orderIndex ?? this.orderIndex,
      archivedAt: archivedAt ?? this.archivedAt,
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
    this.topicOrderIndex = 0,
    this.sectionFlag,
    this.topicKey,
    this.task,
  });

  final int id;
  final int viewId;
  final int? taskId;
  final String? sectionName;
  final int orderIndex;
  final int topicOrderIndex;
  final String? sectionFlag;
  final String? topicKey;
  final Map<String, dynamic>? task;

  factory ViewMembership.fromJson(Map<String, dynamic> json) {
    final order = json['order_index'] as int? ?? 0;
    return ViewMembership(
      id: json['id'] as int,
      viewId: json['view_id'] as int,
      taskId: json['task_id'] as int?,
      sectionName: json['section_name'] as String?,
      orderIndex: order,
      topicOrderIndex: json['topic_order_index'] as int? ?? order,
      sectionFlag: json['section_flag'] as String?,
      topicKey: json['topic_key'] as String?,
      task: json['task'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(json['task'] as Map)
          : null,
    );
  }

  ViewMembership copyWith({
    int? orderIndex,
    int? topicOrderIndex,
    Map<String, dynamic>? task,
    String? sectionName,
    String? sectionFlag,
    String? topicKey,
    bool clearSection = false,
    bool clearTopic = false,
  }) {
    return ViewMembership(
      id: id,
      viewId: viewId,
      taskId: taskId,
      sectionName: clearSection ? null : (sectionName ?? this.sectionName),
      orderIndex: orderIndex ?? this.orderIndex,
      topicOrderIndex: topicOrderIndex ?? this.topicOrderIndex,
      sectionFlag: clearSection ? null : (sectionFlag ?? this.sectionFlag),
      topicKey: clearTopic ? null : (topicKey ?? this.topicKey),
      task: task ?? this.task,
    );
  }

  Map<String, dynamic> toReplaceJson() => {
        'task_id': taskId,
        'section_name': sectionName,
        'order_index': orderIndex,
        'topic_order_index': topicOrderIndex,
        'section_flag': sectionFlag,
        'topic_key': topicKey,
      };
}
