import '../../core/models/app_file.dart';

const paneReorderMaxMainFiles = 4;

enum PaneReorderSection { main, additional }

class PaneReorderState {
  const PaneReorderState({
    required this.main,
    required this.additional,
  });

  final List<AppFile> main;
  final List<AppFile> additional;

  factory PaneReorderState.fromFiles({
    required List<AppFile> mainFiles,
    required List<AppFile> secondaryFiles,
  }) {
    return PaneReorderState(
      main: List<AppFile>.from(mainFiles),
      additional: List<AppFile>.from(secondaryFiles),
    );
  }

  PaneReorderSection? sectionOf(AppFile file) {
    if (main.any((f) => f.id == file.id)) return PaneReorderSection.main;
    if (additional.any((f) => f.id == file.id)) {
      return PaneReorderSection.additional;
    }
    return null;
  }

  int indexInSection(AppFile file, PaneReorderSection section) {
    final list =
        section == PaneReorderSection.main ? main : additional;
    return list.indexWhere((f) => f.id == file.id);
  }
}

/// Applies a drop of [file] from [from]/[fromIndex] into [to] at [toIndex].
PaneReorderState applyPaneReorderDrop({
  required PaneReorderState state,
  required AppFile file,
  required PaneReorderSection from,
  required int fromIndex,
  required PaneReorderSection to,
  required int toIndex,
}) {
  var main = List<AppFile>.from(state.main);
  var additional = List<AppFile>.from(state.additional);

  if (from == PaneReorderSection.main) {
    main.removeAt(fromIndex);
  } else {
    additional.removeAt(fromIndex);
  }

  var insertAt = toIndex;
  if (from == to && fromIndex < toIndex) {
    insertAt--;
  }

  if (to == PaneReorderSection.main) {
    insertAt = insertAt.clamp(0, main.length);
    if (main.length < paneReorderMaxMainFiles) {
      main.insert(insertAt, file);
    } else {
      final evicted = main.removeLast();
      main.insert(insertAt, file);
      additional.insert(0, evicted);
    }
  } else {
    insertAt = insertAt.clamp(0, additional.length);
    additional.insert(insertAt, file);
  }

  return PaneReorderState(main: main, additional: additional);
}

List<AppFile> orderedFiles(PaneReorderState state) =>
    [...state.main, ...state.additional];
