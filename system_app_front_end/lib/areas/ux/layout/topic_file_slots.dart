import '../../files/data/app_file.dart';
import './file_layouts.dart';

/// Which of a topic's files are on screen.
///
/// A layout has a fixed number of slots — `single` one, `split` two, the hero
/// layouts three, `row` and `grid` as many as there are. Files fill those slots
/// in order. A file past the last slot is simply not on screen: not archived,
/// not flagged, just further down the order than the layout has room for. The
/// user brings it back by rearranging the topic.
///
/// Nothing here reads a property of the file. Prominence belongs to the topic's
/// arrangement, so order plus layout is the whole answer.

/// The layout the topic can actually draw with this many files.
///
/// A stored layout that needs more files than exist falls back to the best fit,
/// and is left stored as it is — adding the files back restores it.
String effectiveLayoutId(String layoutId, int fileCount) {
  if (FileLayouts.isAvailable(layoutId, fileCount)) return layoutId;
  return FileLayouts.bestForFileCount(fileCount);
}

/// How many files the layout shows out of [fileCount].
int shownFileCount(String layoutId, int fileCount) {
  if (fileCount <= 0) return 0;
  final capacity = FileLayouts.fixedCapacityFor(
    effectiveLayoutId(layoutId, fileCount),
  );
  if (capacity == null) return fileCount;
  return capacity.clamp(0, fileCount);
}

/// The files the layout has room for, in order.
List<AppFile> shownFiles(List<AppFile> ordered, String layoutId) {
  return ordered.take(shownFileCount(layoutId, ordered.length)).toList();
}

/// The files past the last slot — off screen until the topic is rearranged.
List<AppFile> hiddenFiles(List<AppFile> ordered, String layoutId) {
  return ordered.skip(shownFileCount(layoutId, ordered.length)).toList();
}

/// A topic's files in the one order that decides everything.
List<AppFile> orderedFiles(List<AppFile> files) {
  return [...files]..sort((a, b) {
    final byOrder = a.orderIndex.compareTo(b.orderIndex);
    return byOrder != 0 ? byOrder : a.id.compareTo(b.id);
  });
}
