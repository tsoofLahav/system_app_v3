import './file_layouts.dart';

/// Session peek: shortcut to grid, same shortcut back, forgotten when leaving
/// the topic page. Not persisted.
class GridLayoutPeek {
  int? topicId;
  String? returnLayout;

  void forget() {
    topicId = null;
    returnLayout = null;
  }

  void forgetIfLeft(int? currentTopicId) {
    if (topicId != null && topicId != currentTopicId) forget();
  }

  /// Layout to apply. Updates this peek only when leaving a non-grid layout.
  String take({
    required int topicId,
    required String storedLayout,
    required String shownLayout,
  }) {
    if (shownLayout == FileLayouts.grid) {
      final restore = this.topicId == topicId ? returnLayout : null;
      forget();
      final id = restore == null || restore.isEmpty
          ? FileLayouts.auto
          : FileLayouts.canonicalId(restore);
      if (id == FileLayouts.grid) return FileLayouts.auto;
      return id;
    }
    this.topicId = topicId;
    returnLayout = storedLayout;
    return FileLayouts.grid;
  }
}
