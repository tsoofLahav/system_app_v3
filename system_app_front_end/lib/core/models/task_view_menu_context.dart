import '../registry/task_view_display.dart';

/// Right-click assignment context when the task row is shown in a view pane.
class TaskViewMenuContext {
  const TaskViewMenuContext({
    required this.viewType,
    required this.displayMode,
    this.sectionName,
  });

  final String viewType;
  final TaskViewDisplayMode displayMode;
  final String? sectionName;
}
