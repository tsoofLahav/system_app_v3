import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:system_app_front_end/areas/files/rich_text/rtl/rtl.dart';

void main() {
  tearDown(
    () => WritingDirection.policy.value = TextDirectionPolicy.firstStrong,
  );
  test('app-language policy is shared by SE and object fields', () {
    WritingDirection.policy.value = TextDirectionPolicy.appLanguage;
    expect(
      resolveFieldTextDirection('hello 123', TextDirection.rtl),
      TextDirection.rtl,
    );
    final node = ParagraphNode(id: 'p', text: AttributedText('hello 123'));
    final doc = MutableDocument(nodes: [node]);
    final builder = ambientAwareTextBuilders(TextDirection.rtl)[1];
    final vm =
        builder.createViewModel(doc, node) as ParagraphComponentViewModel;
    expect(vm.textDirection, TextDirection.rtl);
    expect(node.text.toPlainText(), 'hello 123');
  });
  group('AmbientTextDirectionBuilder', () {
    test('empty paragraph under Hebrew ambient is RTL', () {
      final doc = MutableDocument(
        nodes: [ParagraphNode(id: 'p1', text: AttributedText())],
      );
      final builders = ambientAwareTextBuilders(TextDirection.rtl);
      SingleColumnLayoutComponentViewModel? vm;
      for (final b in builders) {
        vm = b.createViewModel(doc, doc.getNodeAt(0)!);
        if (vm != null) break;
      }
      expect(vm, isA<ParagraphComponentViewModel>());
      expect(
        (vm! as ParagraphComponentViewModel).textDirection,
        TextDirection.rtl,
      );
    });

    test('empty paragraph under English ambient is LTR', () {
      final doc = MutableDocument(
        nodes: [ParagraphNode(id: 'p1', text: AttributedText())],
      );
      final builders = ambientAwareTextBuilders(TextDirection.ltr);
      SingleColumnLayoutComponentViewModel? vm;
      for (final b in builders) {
        vm = b.createViewModel(doc, doc.getNodeAt(0)!);
        if (vm != null) break;
      }
      expect(
        (vm! as ParagraphComponentViewModel).textDirection,
        TextDirection.ltr,
      );
    });

    test('Hebrew text is RTL even under LTR ambient', () {
      final doc = MutableDocument(
        nodes: [ParagraphNode(id: 'p1', text: AttributedText('שלום'))],
      );
      final builders = ambientAwareTextBuilders(TextDirection.ltr);
      SingleColumnLayoutComponentViewModel? vm;
      for (final b in builders) {
        vm = b.createViewModel(doc, doc.getNodeAt(0)!);
        if (vm != null) break;
      }
      expect(
        (vm! as ParagraphComponentViewModel).textDirection,
        TextDirection.rtl,
      );
    });

    test('English text is LTR even under RTL ambient', () {
      final doc = MutableDocument(
        nodes: [ParagraphNode(id: 'p1', text: AttributedText('Hello'))],
      );
      final builders = ambientAwareTextBuilders(TextDirection.rtl);
      SingleColumnLayoutComponentViewModel? vm;
      for (final b in builders) {
        vm = b.createViewModel(doc, doc.getNodeAt(0)!);
        if (vm != null) break;
      }
      expect(
        (vm! as ParagraphComponentViewModel).textDirection,
        TextDirection.ltr,
      );
    });
  });
}
