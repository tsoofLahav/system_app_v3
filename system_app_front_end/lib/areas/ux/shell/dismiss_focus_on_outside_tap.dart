import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../files/editor/document_editor_controller.dart';

/// Marks a region where a tap must not steal editor focus — the bottom bar,
/// and an object while its inner field is focused (so insert tools still work).
const keepEditorFocusToken = Object();

class KeepEditorFocus extends StatelessWidget {
  const KeepEditorFocus({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MetaData(
      metaData: keepEditorFocusToken,
      behavior: HitTestBehavior.translucent,
      child: child,
    );
  }
}

/// Closes the software keyboard when a tap lands outside the focused editor.
///
/// Flutter keeps focus on Super Editor / a [TextField] until another focusable
/// widget takes it. Tapping chrome, the canvas, or empty padding does not, so
/// the keyboard stays up. This listens at the shell and unfocuses when the
/// pointer is outside the focused widget's box — not when it is another field
/// (that field then requests focus on the same tap), and not when it hits
/// [KeepEditorFocus] (bottom menus, the open object).
///
/// Does not rebuild the editor tree or notify [AppState].
class DismissFocusOnOutsideTap extends StatelessWidget {
  const DismissFocusOnOutsideTap({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      child: child,
    );
  }

  void _onPointerDown(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.mouse &&
        event.buttons != kPrimaryMouseButton) {
      return;
    }
    dismissPrimaryFocusIfPointerOutside(event.position, viewId: event.viewId);
  }
}

void dismissPrimaryFocusIfPointerOutside(
  Offset globalPosition, {
  int viewId = 0,
}) {
  if (pointerHitsKeepEditorFocus(globalPosition, viewId: viewId)) return;
  final focus = FocusManager.instance.primaryFocus;
  if (focus == null || !focus.hasFocus) return;
  final box = nearestRenderBox(focus.context?.findRenderObject());
  if (box == null || !box.attached) {
    focus.unfocus();
    return;
  }
  final origin = box.localToGlobal(Offset.zero);
  if (!(origin & box.size).contains(globalPosition)) {
    focus.unfocus();
    DocumentEditorRegistry.dismissLiveMarkOnOutsideTap();
  }
}

bool pointerHitsKeepEditorFocus(Offset globalPosition, {int viewId = 0}) {
  final result = HitTestResult();
  GestureBinding.instance.hitTestInView(result, globalPosition, viewId);
  for (final entry in result.path) {
    final target = entry.target;
    if (target is RenderMetaData &&
        identical(target.metaData, keepEditorFocusToken)) {
      return true;
    }
  }
  return false;
}

RenderBox? nearestRenderBox(RenderObject? node) {
  var current = node;
  while (current != null) {
    if (current is RenderBox && current.hasSize) return current;
    current = current.parent;
  }
  return null;
}
