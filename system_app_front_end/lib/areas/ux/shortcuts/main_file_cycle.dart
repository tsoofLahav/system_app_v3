import '../../files/data/app_file.dart';

List<AppFile> rotateMainFilesLeft(List<AppFile> main) {
  if (main.length < 2) return List<AppFile>.from(main);
  return [...main.sublist(1), main.first];
}

List<AppFile> rotateMainFilesRight(List<AppFile> main) {
  if (main.length < 2) return List<AppFile>.from(main);
  return [main.last, ...main.sublist(0, main.length - 1)];
}

/// Next topic file order after cycling **every** live file one step.
///
/// [reverse] walks the other way. Archived files are not in [ordered].
/// Null when there is nothing to cycle.
List<AppFile>? cycledTopicFileOrder({
  required List<AppFile> ordered,
  bool reverse = false,
}) {
  if (ordered.length < 2) return null;
  return reverse ? rotateMainFilesRight(ordered) : rotateMainFilesLeft(ordered);
}

/// @nodoc Kept for older tests — same as [cycledTopicFileOrder].
List<AppFile>? cycledShownFileOrder({
  required List<AppFile> ordered,
  String? layoutId,
  bool reverse = false,
}) {
  return cycledTopicFileOrder(ordered: ordered, reverse: reverse);
}
