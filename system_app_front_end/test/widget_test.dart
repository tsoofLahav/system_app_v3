import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/core/registry/file_registry.dart';

void main() {
  test('project registry includes overview and plan', () {
    final files = FileRegistry.recommendedForTopicType('project');
    expect(files.any((f) => f.type == 'overview'), isTrue);
    expect(files.any((f) => f.type == 'plan'), isTrue);
  });

  test('main topic is reserved name', () {
    expect(FileRegistry.mainTopicName, 'main');
  });
}
