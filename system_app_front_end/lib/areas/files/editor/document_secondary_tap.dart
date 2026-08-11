import 'package:flutter/widgets.dart';

/// Coordinates Super Editor’s document right-click with embed field menus.
///
/// Embed [FormattedTextField]s handle secondary tap themselves. The document
/// [GestureDetector] is translucent and would otherwise open a second menu.
abstract final class DocumentSecondaryTap {
  static bool _embedHandled = false;

  /// Call from an embed field before showing its context menu.
  static void markEmbedHandled() {
    _embedHandled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _embedHandled = false;
    });
  }

  /// True when an embed field already consumed this secondary tap.
  static bool get embedHandled => _embedHandled;
}
