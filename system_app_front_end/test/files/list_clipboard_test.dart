import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:system_app_front_end/areas/files/model/marker_super_editor_bridge.dart';
import 'package:system_app_front_end/areas/files/rich_text/list_text_parse.dart';

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

  test('clipboardLooksLikeList requires a mark on every line', () {
    expect(clipboardLooksLikeList('- one\n- two'), isTrue);
    expect(clipboardLooksLikeList('1. one\n2. two'), isTrue);
    expect(clipboardLooksLikeList('• one\n* two'), isTrue);
    expect(clipboardLooksLikeList('hello\nworld'), isFalse);
    expect(clipboardLooksLikeList('- one\nplain'), isFalse);
    expect(clipboardLooksLikeOrderedList('1. one\n2. two'), isTrue);
    expect(clipboardLooksLikeOrderedList('- one\n- two'), isFalse);
  });

  test('list paste rebuilds ListItemNodes from clipboard prefixes', () {
    final items = listItemsFromClipboard('- milk\n- eggs');
    expect(items, hasLength(2));
    expect(items.every((n) => n.type == ListItemType.unordered), isTrue);
    expect(items[0].text.toPlainText(), 'milk');
    expect(items[1].text.toPlainText(), 'eggs');
  });

  test('marked newline-separated text becomes one item per line', () {
    expect(
      listItemTextsFromMarkedText('milk\neggs\n'),
      ['milk', 'eggs'],
    );
    expect(
      listItemTextsFromMarkedText('- milk\n- eggs'),
      ['milk', 'eggs'],
    );
  });
}
