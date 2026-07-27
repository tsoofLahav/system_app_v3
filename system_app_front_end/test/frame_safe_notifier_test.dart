import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/files/editor/document_editor_controller.dart';
import 'package:system_app_front_end/shared/utils/frame_safe_notifier.dart';

/// Stands in for a document editor: it claims the registry while it lives and
/// gives it up from `dispose`, which is the moment that used to crash.
class _RegisteringEditor extends StatefulWidget {
  const _RegisteringEditor({required this.fileId});

  final int fileId;

  @override
  State<_RegisteringEditor> createState() => _RegisteringEditorState();
}

class _RegisteringEditorState extends State<_RegisteringEditor> {
  @override
  void initState() {
    super.initState();
    DocumentEditorRegistry.register(
      DocumentEditorController(
        fileId: widget.fileId,
        insertAtBlock: (_) async {},
        focusBlock: (_) {},
        flushPendingChanges: () async {},
      ),
    );
  }

  @override
  void dispose() {
    DocumentEditorRegistry.unregister(widget.fileId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

/// A listener of the same kind the shells and the insert bar use.
Widget _harness({required bool showEditor}) {
  return MaterialApp(
    home: Column(
      children: [
        ListenableBuilder(
          listenable: DocumentEditorRegistry.notifier,
          builder: (context, _) => Text(
            DocumentEditorRegistry.active == null ? 'no editor' : 'editor',
            textDirection: TextDirection.ltr,
          ),
        ),
        if (showEditor) const _RegisteringEditor(fileId: 7),
      ],
    ),
  );
}

void main() {
  testWidgets('closing an editor does not rebuild a tree being unmounted', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(showEditor: true));
    await tester.pump();
    expect(find.text('editor'), findsOneWidget);

    // The editor leaves. Its `dispose` runs while Flutter has the tree locked,
    // so a listener rebuilt on the spot would throw.
    await tester.pumpWidget(_harness(showEditor: false));
    expect(tester.takeException(), isNull);

    await tester.pump();
    expect(find.text('no editor'), findsOneWidget);
  });

  testWidgets('a bump while idle arrives without waiting for a frame', (
    tester,
  ) async {
    final notifier = FrameSafeNotifier();
    var notified = 0;
    notifier.addListener(() => notified++);

    // Nothing schedules a frame here. A notification that waited for one would
    // never be delivered.
    notifier.notify();
    expect(notified, 1);
  });
}
