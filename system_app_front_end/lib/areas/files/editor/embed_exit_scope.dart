import 'package:flutter/widgets.dart';

/// Inner fields read this so Shift+Enter can leave the object (a TextField
/// would otherwise insert a newline and never bubble to [Shortcuts]).
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
