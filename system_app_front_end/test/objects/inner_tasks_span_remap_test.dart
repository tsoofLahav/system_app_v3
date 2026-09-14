import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/objects/data/inner_tasks.dart';
import 'package:system_app_front_end/areas/files/rich_text/text_formatting.dart';

/// A connected span living after a legacy `- [ ] ` checkbox line must not
/// drift when that line is toggled to done (it shortens to `☑ `). AppState's
/// toggle paths must run new text through [remapSpansForTextEdit] against
/// the raw pre-toggle body, not persist the caller's spans untouched.
void main() {
  test('setAllInnerTasks shortens a legacy line; remap keeps later spans put', () {
    const body = '- [ ] one\nlink this word';
    final wordStart = body.indexOf('word');
    final wordEnd = wordStart + 'word'.length;
    final spans = [
      {'start': wordStart, 'end': wordEnd, 'descriptionLink': true},
    ];

    final next = setAllInnerTasks(body, done: true);
    expect(next, '☑ one\nlink this word');
    // The legacy line shrank by 4 chars ("- [ ] " -> "☑ ").
    expect(next.length, body.length - 4);

    final remapped = remapSpansForTextEdit(spans, body, next);
    final newWordStart = next.indexOf('word');
    expect(remapped.single['start'], newWordStart);
    expect(remapped.single['end'], newWordStart + 'word'.length);
    expect(next.substring(remapped.single['start'] as int, remapped.single['end'] as int), 'word');
  });

  test('toggleInnerTaskAt on a legacy mark also shortens; remap tracks it', () {
    const body = '- [ ] buy milk\nlink this word';
    final wordStart = body.indexOf('word');
    final spans = [
      {'start': wordStart, 'end': wordStart + 'word'.length, 'descriptionLink': true},
    ];
    final mark = parseInnerTaskLines(body).first.markStart;

    final next = toggleInnerTaskAt(body, mark);
    expect(next, isNotNull);
    expect(next, '☑ buy milk\nlink this word');

    final remapped = remapSpansForTextEdit(spans, body, next!);
    final newWordStart = next.indexOf('word');
    expect(remapped.single['start'], newWordStart);
    expect(next.substring(remapped.single['start'] as int, remapped.single['end'] as int), 'word');
  });
}
