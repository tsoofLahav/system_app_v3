import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/objects/data/inner_tasks.dart';

void main() {
  test('parse and unanimous ignore prose', () {
    const body = '- [ ] one\nkeep prose\n- [x] two';
    final items = parseInnerTaskLines(body);
    expect(items.map((item) => item.title), ['one', 'two']);
    expect(items.map((item) => item.done), [false, true]);
    expect(innerTasksUnanimous(body), isNull);
    expect(innerTasksUnanimous('- [x] a\n- [x] b'), isTrue);
    expect(innerTasksUnanimous('- [ ] a\n- [ ] b'), isFalse);
    expect(innerTasksUnanimous('just prose'), isNull);
  });

  test('set all and toggle keep surrounding text', () {
    const body = 'note\n- [ ] one\n- [x] two';
    expect(setAllInnerTasks(body, done: true), 'note\n- [x] one\n- [x] two');
    expect(
      setAllInnerTasks('note\n- [x] one\n- [x] two', done: false),
      'note\n- [ ] one\n- [ ] two',
    );
    final mark = parseInnerTaskLines(body).first.markStart;
    expect(toggleInnerTaskAt(body, mark), 'note\n- [x] one\n- [x] two');
    expect(tapHitsInnerTaskMark(body, mark), isTrue);
    expect(tapHitsInnerTaskMark(body, 0), isFalse);
  });

  test('combined title stays out of the checklist', () {
    const combined = 'Title\n- [ ] milk';
    expect(tapHitsCombinedInnerMark(combined, 0), isFalse);
    expect(combinedInnerTasksUnanimous(combined), isFalse);
    final toggled = toggleCombinedInnerTask(
      combined,
      parseInnerTaskLines('- [ ] milk').first.markStart + 'Title\n'.length,
    );
    expect(toggled, 'Title\n- [x] milk');
    expect(setAllCombinedInnerTasks(combined, done: true), 'Title\n- [x] milk');
  });

  test('typing a bare dash becomes a checkbox', () {
    final next = promoteBareDashToCheckbox('Title\n- ', 8);
    expect(next, isNotNull);
    expect(next!.text, 'Title\n- [ ] ');
    expect(next.caret, 12);
  });

  test('Enter on a filled inner line adds another', () {
    const combined = 'Title\n- [ ] milk';
    final next = insertInnerTaskLineOnEnter(combined, combined.length);
    expect(next, isNotNull);
    expect(next!.text, 'Title\n- [ ] milk\n- [ ] ');
  });

  test('Enter on an empty inner line drops the prefix', () {
    const combined = 'Title\n- [ ] ';
    final next = insertInnerTaskLineOnEnter(combined, combined.length);
    expect(next, isNotNull);
    expect(next!.text, 'Title\n');
  });
}
