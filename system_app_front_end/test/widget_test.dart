import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/core/registry/file_behavior_registry.dart';
import 'package:system_app_front_end/core/registry/file_registry.dart';

void main() {
  test('project registry includes summary, tasks, execution, doc, and plan', () {
    final files = FileRegistry.recommendedForTopicType('project');
    expect(files.any((f) => f.type == 'overview' && f.isMain), isTrue);
    expect(files.any((f) => f.type == 'tasks' && f.isMain), isTrue);
    expect(files.any((f) => f.type == 'execution' && f.isMain), isTrue);
    expect(files.any((f) => f.type == 'doc' && !f.isMain), isTrue);
    expect(files.any((f) => f.type == 'plan' && !f.isMain), isTrue);
    expect(files.where((f) => f.isMain).length, 3);
  });

  test('execution profile seeds header and list', () {
    final blocks = FileBehaviorRegistry.defaultBlocksForFileType('execution');
    expect(blocks.map((b) => b.type), ['header', 'list', 'text']);
    expect(
      FileBehaviorRegistry.contextMenuForFileType('execution'),
      containsAll(['text', 'header', 'summary', 'list', 'graph', 'image']),
    );
  });

  test('main topic is reserved name', () {
    expect(FileRegistry.mainTopicName, 'main');
  });
}
