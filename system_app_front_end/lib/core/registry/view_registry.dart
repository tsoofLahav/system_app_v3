class TaskViewDefinition {
  const TaskViewDefinition({required this.type, required this.label});
  final String type;
  final String label;
}

/// Backend task view types — separate from topic sidebar navigation.
abstract final class ViewRegistry {
  static const List<TaskViewDefinition> views = [
    TaskViewDefinition(type: 'daily', label: 'Daily'),
    TaskViewDefinition(type: 'weekly', label: 'Weekly'),
    TaskViewDefinition(type: 'monthly', label: 'Monthly'),
    TaskViewDefinition(type: 'quarterly', label: 'Quarterly'),
    TaskViewDefinition(type: 'arrangements', label: 'Arrangements'),
    TaskViewDefinition(type: 'missions', label: 'Missions'),
  ];

  static String labelFor(String type) {
    for (final view in views) {
      if (view.type == type) return view.label;
    }
    return type;
  }
}
