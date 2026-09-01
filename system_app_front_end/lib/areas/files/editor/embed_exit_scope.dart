import 'package:flutter/widgets.dart';

/// Inner fields read this so Escape (and Enter in info) can leave the object
/// instead of inserting a newline. Shift+Enter / ⌘Enter / Ctrl+Enter still
/// insert a line.
class EmbedExitScope extends InheritedWidget {
  const EmbedExitScope({
    super.key,
    required this.nodeId,
    required this.onExit,
    required super.child,
  });

  final String nodeId;
  final void Function(String nodeId) onExit;

  static EmbedExitScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<EmbedExitScope>();
  }

  @override
  bool updateShouldNotify(EmbedExitScope oldWidget) {
    return nodeId != oldWidget.nodeId || onExit != oldWidget.onExit;
  }
}
