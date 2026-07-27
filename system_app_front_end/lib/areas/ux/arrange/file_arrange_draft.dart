import '../../files/data/app_file.dart';
import '../layout/topic_file_slots.dart';
import '../shortcuts/main_file_cycle.dart';

/// The uncommitted arrangement of a topic: one ordered list of files and the
/// layout drawn over it.
///
/// There is no second list of "additional" files. The layout's slots reach a
/// certain distance down the order, and everything past that is off screen —
/// so promoting a file is a move up the order, and demoting it is a move to the
/// end. Nothing is written until the overlay is committed.
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

  /// Makes a shown file the first one, keeping the others in order.
  bool moveShownToFirst(int shownIndex) {
    if (shownIndex <= 0 || shownIndex >= shownCount) return false;
    ordered.insert(0, ordered.removeAt(shownIndex));
    return true;
  }

  /// Brings a hidden file into the last slot, pushing out whatever sat there.
  bool show(int hiddenIndex) {
    if (hiddenIndex < 0 || hiddenIndex >= hidden.length) return false;
    final lastSlot = shownCount - 1;
    if (lastSlot < 0) return false;
    final file = hidden[hiddenIndex];
    ordered.removeAt(ordered.indexWhere((f) => f.id == file.id));
    ordered.insert(lastSlot, file);
    return true;
  }

  /// Sends a shown file to the end of the order, off screen.
  bool hide(int shownIndex) {
    if (shownIndex < 0 || shownIndex >= shownCount) return false;
    ordered.add(ordered.removeAt(shownIndex));
    return true;
  }

  /// Cycles which file leads, so every shown file can reach the first slot with
  /// the arrow keys alone. Only the shown files move; the hidden ones keep
  /// their place at the end.
  bool rotateShownLeft() => _rotate(rotateMainFilesLeft);

  bool rotateShownRight() => _rotate(rotateMainFilesRight);

  bool _rotate(List<AppFile> Function(List<AppFile>) rotation) {
    if (shownCount < 2) return false;
    ordered = [...rotation(shown), ...hidden];
    return true;
  }
}
