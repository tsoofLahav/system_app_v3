import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/core/ai/ai_context.dart';

void main() {
  group('AiContextResolver', () {
    const topicId = 1;

    AiFocus focus(String text, TextSelection selection) => AiFocus(
          fileId: 10,
          blockId: 20,
          fullText: text,
          selection: selection,
        );

    test('uses non-collapsed selection', () {
      const text = 'first line\nselected text\nthird';
      final result = AiContextResolver.resolve(
        topicId: topicId,
        focus: focus(text, const TextSelection(baseOffset: 11, extentOffset: 24)),
        lastTaskTitle: null,
        lastTaskFileId: null,
      );

      expect(result?.text, 'selected text');
      expect(result?.sourceType, AiSourceType.selection);
    });

    test('uses current line when caret is collapsed', () {
      const text = 'first line\nsecond line\n';
      final result = AiContextResolver.resolve(
        topicId: topicId,
        focus: focus(text, const TextSelection.collapsed(offset: 17)),
        lastTaskTitle: null,
        lastTaskFileId: null,
      );

      expect(result?.text, 'second line');
      expect(result?.sourceType, AiSourceType.line);
    });

    test('does not fall back to previous line on empty current line', () {
      const text = 'buy milk\n';
      final result = AiContextResolver.resolve(
        topicId: topicId,
        focus: focus(text, const TextSelection.collapsed(offset: 9)),
        lastTaskTitle: 'fallback task',
        lastTaskFileId: 5,
      );

      expect(result?.text, 'fallback task');
      expect(result?.sourceType, AiSourceType.task);
    });

    test('uses last line when caret is at end of file', () {
      const text = 'line one\nline two';
      final result = AiContextResolver.resolve(
        topicId: topicId,
        focus: focus(text, const TextSelection.collapsed(offset: 15)),
        lastTaskTitle: null,
        lastTaskFileId: null,
      );

      expect(result?.text, 'line two');
      expect(result?.sourceType, AiSourceType.line);
    });

    test('falls back to task title when no focus text', () {
      final result = AiContextResolver.resolve(
        topicId: topicId,
        focus: null,
        lastTaskTitle: '  Buy eggs  ',
        lastTaskFileId: 5,
      );

      expect(result?.text, 'Buy eggs');
      expect(result?.sourceType, AiSourceType.task);
      expect(result?.fileId, 5);
    });
  });
}
