import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:system_app_front_end/areas/files/model/marker_super_editor_bridge.dart';

void main() {
  test('unordered list clipboard lines keep the dash', () {
    final item = ListItemNode.unordered(
      id: 'a',
      text: AttributedText('Hello'),
    );
    expect(listItemClipboardLine(item, 0, ordered: false), '- Hello');
    expect(listItemClipboardPrefix(ordered: false, index: 0), '- ');
  });

  test('ordered list clipboard lines keep the number', () {
    final item = ListItemNode.ordered(
      id: 'b',
      text: AttributedText('World'),
    );
    expect(listItemClipboardLine(item, 1, ordered: true), '2. World');
    expect(listItemClipboardPrefix(ordered: true, index: 1), '2. ');
  });
}
