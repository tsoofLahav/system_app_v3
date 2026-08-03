import 'package:flutter/widgets.dart';

/// True while [EmbedBlockHost] is in Move Mode — children can switch to a
/// compact, non-editing layout so the glass frame hugs content.
class EmbedMoveModeScope extends InheritedWidget {
  const EmbedMoveModeScope({
    super.key,
    required this.active,
    required super.child,
  });

  final bool active;

  static bool of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<EmbedMoveModeScope>()
            ?.active ??
        false;
  }

  @override
  bool updateShouldNotify(EmbedMoveModeScope oldWidget) =>
      active != oldWidget.active;
}
