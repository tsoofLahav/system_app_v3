import '../../files/data/app_file.dart';
enum PaneReorderSection { main, additional }

class PaneReorderState {
  PaneReorderState({required this.main, required this.additional});

  final List<AppFile> main;
  final List<AppFile> additional;
}

PaneReorderState applyPaneReorderDrop({
  required PaneReorderState state,
  required AppFile file,
  required PaneReorderSection from,
  required int fromIndex,
  required PaneReorderSection to,
  required int toIndex,
}) {
  final main = List<AppFile>.from(state.main);
  final additional = List<AppFile>.from(state.additional);

  if (from == PaneReorderSection.main) {
    main.removeAt(fromIndex);
  } else {
    additional.removeAt(fromIndex);
  }

  if (to == PaneReorderSection.main) {
    main.insert(toIndex.clamp(0, main.length), file);
  } else {
    additional.insert(toIndex.clamp(0, additional.length), file);
  }

  return PaneReorderState(main: main, additional: additional);
}

List<AppFile> essenceFiles(List<AppFile> files) =>
    files.where((f) => f.isEssence).toList();

List<AppFile> additionalFiles(List<AppFile> files) =>
    files.where((f) => !f.isEssence).toList();
