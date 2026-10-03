import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/objects/data/inner_lists.dart';
import 'package:system_app_front_end/areas/objects/data/inner_tasks.dart';

void main() {
  test('dash starts bullets, star starts tasks, only at a body line start', () {
    expect(promoteBareDashToInnerList('Title\n- ', 8)!.text, 'Title\n• ');
    expect(promoteBareDashToInnerList('Title\n  - ', 10)!.text, 'Title\n  • ');
    expect(promoteBareStarToCheckbox('Title\n- ', 8), isNull);
    expect(promoteBareDashToInnerList('Title\n* ', 8), isNull);
    expect(promoteBareStarToCheckbox('Title\n* ', 8)!.text, 'Title\n☐ ');
    expect(promoteBareDashToInnerList('- ', 2), isNull);
    expect(promoteBareDashToInnerList('Title\ntext - ', 13), isNull);
    expect(promoteBareDashToInnerList('Title\n-', 7), isNull);
    expect(promoteBareDashToInnerList('Title\n', 6), isNull);
  });
  test('insert in title or empty body, without modifying title', () {
    expect(insertInnerList('Title', 2, 2).text, 'Title\n• ');
    expect(insertInnerList('Title\n', 6, 6).text, 'Title\n• ');
    expect(insertInnerList('Title\nbody', 2, 2).text, 'Title\n• \nbody');
  });
  test(
    'selected lines become bullets and ignore the title and blank lines',
    () {
      const text = 'Title\nfirst\n\n☑ second\n  third';
      final next = insertInnerList(text, 0, text.length);
      expect(next.text, 'Title\n• first\n\n• second\n  • third');
      expect(parseInnerTaskLines(next.text), isEmpty);
      expect(innerTasksUnanimous(next.text), isNull);
    },
  );
  test('Enter splits at caret, keeps indentation and exits empty bullets', () {
    const text = 'Title\n  • first second';
    final split = continueInnerList(text, text.indexOf('second'))!;
    expect(split.text, 'Title\n  • first \n  • second');
    expect(continueInnerList('Title\n• ', 8)!.text, 'Title\n');
    expect(continueInnerList('Title\nprose', 9), isNull);
  });
  test('Backspace removes the bullet without deleting item text', () {
    expect(backspaceInnerList('Title\n• milk', 8)!.text, 'Title\nmilk');
    expect(backspaceInnerList('Title\n• milk', 9), isNull);
    expect(backspaceInnerList('Title\n• ', 8)!.text, 'Title\n');
  });
  test('bullet-to-checklist conversion removes the ordinary bullet', () {
    const text = 'Title\n• first\n• second';
    expect(
      convertSelectionToInnerTasks(text, 6, text.length).text,
      'Title\n☐ first\n☐ second',
    );
    expect(promoteBareStarToCheckbox('Title\n* ', 8)!.text, 'Title\n☐ ');
  });
}
