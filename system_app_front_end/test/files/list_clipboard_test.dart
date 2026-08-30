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

  test('splitPastedTaskLines turns a paragraph into first + following tasks', () {
    final split = splitPastedTaskLines('Buy milk\nEggs\nBread');
    expect(split, isNotNull);
    expect(split!.first, 'Buy milk');
    expect(split.following, ['Eggs', 'Bread']);
    expect(splitPastedTaskLines('just one line'), isNull);
    expect(splitPastedTaskLines('- one\n- two'), isNotNull);
    expect(splitPastedTaskLines('- one\n- two')!.following, ['two']);
  });

  test('plain lines split even without list prefixes or Unix newlines', () {
    expect(parsePastedListText('one\ntwo\nthree'), ['one', 'two', 'three']);
    expect(parsePastedListText('one\rtwo\rthree'), ['one', 'two', 'three']);
    expect(parsePastedListText('one\r\ntwo'), ['one', 'two']);
    expect(parsePastedListText('one\u2028two\u2029three'), [
      'one',
      'two',
      'three',
    ]);
    final split = splitPastedTaskLines('one\ntwo');
    expect(split?.first, 'one');
    expect(split?.following, ['two']);
  });
}
