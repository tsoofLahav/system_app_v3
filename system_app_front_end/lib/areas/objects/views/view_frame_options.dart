/// A home list already used somewhere in the view (for choose-list).
class ViewFrameListOption {
  const ViewFrameListOption({
    required this.taskListId,
    required this.title,
  });

  final int taskListId;
  final String title;
}

class ViewSectionOption {
  const ViewSectionOption({
    required this.name,
    this.flag,
  });

  final String name;
  final String? flag;
}

class ViewTopicOption {
  const ViewTopicOption({
    required this.key,
    required this.label,
  });

  /// `topic_<id>`, or empty string for no-topic.
  final String key;
  final String label;
}
