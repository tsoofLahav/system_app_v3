import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:system_app_front_end/areas/files/editor/document_editor_controller.dart';
import 'package:system_app_front_end/areas/files/editor/super_document_editor.dart';

void main() {
  test('phone object-gate notifies only when enter/leave change', () {
    final gate = PhoneObjectGateSignal();
    expect(gate.shouldNotify(canEnter: false, canLeave: false), isFalse);
    expect(gate.shouldNotify(canEnter: true, canLeave: false), isTrue);
    expect(gate.shouldNotify(canEnter: true, canLeave: false), isFalse);
    expect(gate.shouldNotify(canEnter: true, canLeave: true), isTrue);
    expect(gate.shouldNotify(canEnter: false, canLeave: false), isTrue);
    expect(gate.shouldNotify(canEnter: false, canLeave: false), isFalse);
  });

  test('file editor IME turns off autocorrect and suggestions', () {
    expect(kFileEditorImeConfiguration.enableAutocorrect, isFalse);
    expect(kFileEditorImeConfiguration.enableSuggestions, isFalse);
    expect(const SuperEditorImeConfiguration().enableAutocorrect, isTrue);
    expect(const SuperEditorImeConfiguration().enableSuggestions, isTrue);
  });
}
