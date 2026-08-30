import '../../files/data/app_file.dart';
import '../layout/topic_file_slots.dart';

/// The uncommitted arrangement of a topic: one ordered list of files and the
/// layout drawn over it.
///
/// There is no second list of "additional" files. The layout's slots reach a
/// certain distance down the order, and everything past that is off screen.
/// Dragging a chip across that cut is how a file comes on or off screen.
/// Nothing is written until the overlay is committed.
class FileArrangeDraft {
  FileArrangeDraft({required List<AppFile> ordered, required this.layoutId})
      : ordered = List<AppFile>.from(ordered);

  List<AppFile> ordered;
  String layoutId;

  /// Files the layout has room for.
  List<AppFile> get shown => shownFiles(ordered, layoutId);

  /// Files past the last slot — reachable only from here.
  List<AppFile> get hidden => hiddenFiles(ordered, layoutId);

  int get shownCount => shown.length;

  void setLayoutId(String value) {
    layoutId = value;
  }

  /// Place the file at [from] so it occupies [to] in the resulting list.
  ///
  /// Both indices are in [ordered]. No-op when they match or [from] is out of
  /// range. [to] is clamped to a valid final index.
  bool move(int from, int to) {
    final n = ordered.length;
    if (n == 0) return false;
    if (from < 0 || from >= n) return false;
    final dest = to.clamp(0, n - 1);
    if (from == dest) return false;
    final file = ordered.removeAt(from);
    ordered.insert(dest, file);
    return true;
  }
}
