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
    expect(innerTasksUnanimous('☐ a\n☑ b'), isNull);
  });

  test('set all and toggle keep surrounding text', () {
    const body = 'note\n- [ ] one\n- [x] two';
    expect(setAllInnerTasks(body, done: true), 'note\n☑ one\n☑ two');
    expect(
      setAllInnerTasks('note\n☑ one\n☑ two', done: false),
      'note\n☐ one\n☐ two',
    );
    final mark = parseInnerTaskLines(body).first.markStart;
    expect(toggleInnerTaskAt(body, mark), 'note\n☑ one\n- [x] two');
    expect(tapHitsInnerTaskMark(body, mark), isTrue);
    expect(tapHitsInnerTaskMark(body, 0), isFalse);
  });

  test('combined title stays out of the checklist', () {
    const combined = 'Title\n☐ milk';
    expect(tapHitsCombinedInnerMark(combined, 0), isFalse);
    expect(combinedInnerTasksUnanimous(combined), isFalse);
    final toggled = toggleCombinedInnerTask(
      combined,
      parseInnerTaskLines('☐ milk').first.markStart + 'Title\n'.length,
    );
    expect(toggled, 'Title\n☑ milk');
    expect(setAllCombinedInnerTasks(combined, done: true), 'Title\n☑ milk');
  });

  test('typing a bare dash becomes a checkbox', () {
    final next = promoteBareDashToCheckbox('Title\n- ', 8);
    expect(next, isNotNull);
    expect(next!.text, 'Title\n☐ ');
    expect(next.caret, 'Title\n☐ '.length);
  });

  test('Enter on a filled inner line adds another', () {
    const combined = 'Title\n☐ milk';
    final next = insertInnerTaskLineOnEnter(combined, combined.length);
    expect(next, isNotNull);
    expect(next!.text, 'Title\n☐ milk\n☐ ');
  });

  test('Enter on an empty inner line drops the prefix', () {
    const combined = 'Title\n☐ ';
    final next = insertInnerTaskLineOnEnter(combined, combined.length);
    expect(next, isNotNull);
    expect(next!.text, 'Title\n');
  });

  test('menu insert adds an empty checkbox line', () {
    expect(insertInnerTaskAtCaret('Title', 5).text, 'Title\n☐ ');
    final afterProse = insertInnerTaskAtCaret('Title\nnote', 10);
    expect(afterProse.text, 'Title\nnote\n☐ ');
    final afterItem = insertInnerTaskAtCaret('Title\n☐ milk', 12);
    expect(afterItem.text, 'Title\n☐ milk\n☐ ');
  });

  test('canonicalize strips dash and rewrites brackets', () {
    expect(
      canonicalizeInnerTaskMarks('- [ ] a\n- [x] b'),
      '☐ a\n☑ b',
    );
    expect(canonicalizeInnerTaskMarks('- ☐ a\n- ☑ b'), '☐ a\n☑ b');
    expect(canonicalizeInnerTaskMarks('☐ a\n☑ b'), '☐ a\n☑ b');
  });

  test('selection converts marked lines into checklist items', () {
    const combined = 'Title\nbuy milk\nbuy eggs\nnote';
    // Mark both shopping lines (offsets in combined).
    final start = 'Title\n'.length;
    final end = 'Title\nbuy milk\nbuy eggs'.length;
    final next = convertSelectionToInnerTasks(combined, start, end);
    expect(next.text, 'Title\n☐ buy milk\n☐ buy eggs\nnote');
  });
}
