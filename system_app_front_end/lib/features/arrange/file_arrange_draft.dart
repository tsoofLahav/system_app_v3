import '../../core/models/app_file.dart';
import '../../shared/widgets/pane_reorder_logic.dart';

class FileArrangeDraft {
  FileArrangeDraft({
    required List<AppFile> main,
    required List<AppFile> additional,
    required this.layoutId,
  })  : main = List<AppFile>.from(main),
        additional = List<AppFile>.from(additional);

  List<AppFile> main;
  List<AppFile> additional;
  String layoutId;

  int get mainCount => main.length;

  List<AppFile> get ordered => [...main, ...additional];

  void setLayoutId(String value) {
    layoutId = value;
  }

  bool moveMainToFirst(int index) {
    if (index <= 0 || index >= main.length) return false;
    final file = main.removeAt(index);
    main.insert(0, file);
    return true;
  }

  bool promoteFromAdditional(int additionalIndex) {
    if (additionalIndex < 0 || additionalIndex >= additional.length) {
      return false;
    }

    final next = applyPaneReorderDrop(
      state: PaneReorderState(main: main, additional: additional),
      file: additional[additionalIndex],
      from: PaneReorderSection.additional,
      fromIndex: additionalIndex,
      to: PaneReorderSection.main,
      toIndex: main.length,
    );
    main = next.main;
    additional = next.additional;
    return true;
  }
}
