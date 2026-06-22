class LineChangeRegion {
  const LineChangeRegion({
    required this.start,
    required this.removed,
    required this.added,
  });

  final int start;
  final List<String> removed;
  final List<String> added;
}

/// Finds the edited middle region between two line lists (prefix/suffix match).
LineChangeRegion? diffLineRegion(List<String> oldLines, List<String> newLines) {
  var start = 0;
  final shared = oldLines.length < newLines.length
      ? oldLines.length
      : newLines.length;
  while (start < shared && oldLines[start] == newLines[start]) {
    start++;
  }

  var endOld = oldLines.length;
  var endNew = newLines.length;
  while (endOld > start &&
      endNew > start &&
      oldLines[endOld - 1] == newLines[endNew - 1]) {
    endOld--;
    endNew--;
  }

  if (start >= endOld && start >= endNew) {
    return null;
  }

  return LineChangeRegion(
    start: start,
    removed: oldLines.sublist(start, endOld),
    added: newLines.sublist(start, endNew),
  );
}
