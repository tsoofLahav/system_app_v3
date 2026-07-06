import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/core/models/app_file.dart';
import 'package:system_app_front_end/core/models/block.dart';
import 'package:system_app_front_end/core/models/task.dart';
import 'package:system_app_front_end/features/bring_file/bring_file_preview.dart';

AppFile _file() => const AppFile(id: 1, topicId: 2, name: 'Plan', type: 'doc');

Block _block(String type, String text, {int id = 1}) => Block(
      id: id,
      fileId: 1,
      type: type,
      content: {'text': text},
    );

void main() {
  test('previewLinesFromBlocks collects headers and text lines', () {
    final lines = previewLinesFromBlocks([
      _block('header', 'Overview', id: 1),
      _block('text', 'First line\nSecond line', id: 2),
      _block('text', 'Third line', id: 3),
    ]);

    expect(lines, ['Overview', 'First line', 'Second line', 'Third line']);
  });

  test('previewLinesForFile falls back to task titles', () async {
    final lines = await previewLinesForFile(
      _file(),
      [_block('task_list', '', id: 9)],
      (blockId) async {
        expect(blockId, 9);
        return [
          const Task(
            id: 1,
            blockId: 9,
            title: 'Ship feature',
            status: 'active',
          ),
        ];
      },
    );

    expect(lines, ['• Ship feature']);
  });
}
