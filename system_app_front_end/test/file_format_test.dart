import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/core/models/app_file.dart';
import 'package:system_app_front_end/core/registry/file_registry.dart';
import 'package:system_app_front_end/shared/widgets/pane_reorder_logic.dart';

AppFile _file(int id, {bool? isMain}) => AppFile(
      id: id,
      topicId: 1,
      name: 'File $id',
      type: 'text',
      isMain: isMain,
    );

void main() {
  test('main topic resolves main vs additional from registry', () {
    expect(
      FileRegistry.isMainFile(
        topicType: 'area',
        fileType: 'tasks',
        isMainTopic: true,
      ),
      isFalse,
    );
    expect(
      FileRegistry.isMainFile(
        topicType: 'area',
        fileType: 'plan',
        isMainTopic: true,
      ),
      isTrue,
    );
    expect(
      FileRegistry.isMainFile(
        topicType: 'area',
        fileType: 'main',
        isMainTopic: true,
      ),
      isTrue,
    );
  });

  test('main section holds at most three files when reordering', () {
    expect(paneReorderMaxMainFiles, 3);

    final state = PaneReorderState.fromFiles(
      mainFiles: [_file(1), _file(2), _file(3)],
      secondaryFiles: [_file(4)],
    );

    final next = applyPaneReorderDrop(
      state: state,
      file: _file(4),
      from: PaneReorderSection.additional,
      fromIndex: 0,
      to: PaneReorderSection.main,
      toIndex: 3,
    );

    expect(next.main.length, 3);
    expect(next.main.map((f) => f.id), [1, 2, 4]);
    expect(next.additional.first.id, 3);
  });
}
