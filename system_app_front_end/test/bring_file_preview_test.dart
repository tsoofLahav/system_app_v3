import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/core/models/block.dart';
import 'package:system_app_front_end/core/models/task.dart';
import 'package:system_app_front_end/features/bring_file/bring_file_preview.dart';

Block _block(String type, String text, {int id = 1}) => Block(
      id: id,
      fileId: 1,
      type: type,
      content: {'text': text},
    );

void main() {
  test('previewDataForFile loads task data for task_list blocks', () async {
    final data = await previewDataForFile(
      [
        _block('header', 'Overview', id: 1),
        _block('task_list', '', id: 9),
      ],
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

    expect(data.blocks, hasLength(2));
    expect(data.tasksByBlockId[9], hasLength(1));
    expect(data.tasksByBlockId[9]!.first.title, 'Ship feature');
  });

  test('previewDataForFile skips task loading for non-task blocks', () async {
    final data = await previewDataForFile(
      [_block('text', 'Hello', id: 3)],
      (_) async => throw StateError('should not load tasks'),
    );

    expect(data.blocks, hasLength(1));
    expect(data.tasksByBlockId, isEmpty);
  });
}
