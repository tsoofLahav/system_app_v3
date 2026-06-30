import '../registry/task_view_display.dart';

abstract final class ViewPaneKeys {
  static const noTopic = '__no_topic__';
  static const automations = 'automations';
}

class ViewPaneSyncContext {
  const ViewPaneSyncContext({
    required this.viewType,
    required this.displayMode,
    this.sectionName,
    this.topicKey,
  });

  final String viewType;
  final TaskViewDisplayMode displayMode;
  final String? sectionName;
  final String? topicKey;

  String get snapshotKey =>
      'viewPane:$viewType:${sectionName ?? ''}:${topicKey ?? ''}';

  String zoneSnapshotKey(bool done) => '$snapshotKey:${done ? 'done' : 'active'}';
}
