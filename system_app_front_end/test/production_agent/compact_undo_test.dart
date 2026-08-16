import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/production_agent/compact_undo_toast.dart';
import 'package:system_app_front_end/core/l10n/app_strings.dart';

void main() {
  final s = AppStrings.en;

  test('summary for single add / edit / remove', () {
    CompactUndoCard card(String op, String text) => CompactUndoCard(
          fileId: 1,
          fileName: 'Notes',
          topicId: 2,
          topicName: 'Health',
          oldDocumentJson: 'x',
          changes: [CompactUndoChange(op: op, text: text)],
        );

    expect(
      compactUndoSummaryLine(s, card('add', 'hello')),
      '1 line was added: "hello"',
    );
    expect(
      compactUndoSummaryLine(s, card('change', 'hello')),
      '1 line was edited: "hello"',
    );
    expect(
      compactUndoSummaryLine(s, card('remove', 'bye')),
      '1 line was removed: "bye"',
    );
  });

  test('summary for many changes', () {
    final card = CompactUndoCard(
      fileId: 1,
      fileName: 'Notes',
      topicId: 2,
      topicName: 'Health',
      oldDocumentJson: 'x',
      changes: const [
        CompactUndoChange(op: 'add', text: 'a'),
        CompactUndoChange(op: 'remove', text: 'b'),
      ],
    );
    expect(compactUndoSummaryLine(s, card), '2 changes were made');
    expect(
      compactUndoHeadline(s, card),
      'In file Notes, of Health',
    );
  });
}
