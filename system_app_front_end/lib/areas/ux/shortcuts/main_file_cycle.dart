import '../../files/data/app_file.dart';
import '../layout/topic_file_slots.dart';

List<AppFile> rotateMainFilesLeft(List<AppFile> main) {
  if (main.length < 2) return List<AppFile>.from(main);
  return [...main.sublist(1), main.first];
}

List<AppFile> rotateMainFilesRight(List<AppFile> main) {
  if (main.length < 2) return List<AppFile>.from(main);
  return [main.last, ...main.sublist(0, main.length - 1)];
}

/// Next topic file order after cycling the on-screen band one step.
///
/// [reverse] walks the other way. Hidden files stay after the shown band.
/// Null when there is nothing to cycle.
List<AppFile>? cycledShownFileOrder({
  required List<AppFile> ordered,
  required String layoutId,
  bool reverse = false,
}) {
  final shown = shownFiles(ordered, layoutId);
  if (shown.length < 2) return null;
  final rotated =
      reverse ? rotateMainFilesRight(shown) : rotateMainFilesLeft(shown);
  return [...rotated, ...hiddenFiles(ordered, layoutId)];
}
