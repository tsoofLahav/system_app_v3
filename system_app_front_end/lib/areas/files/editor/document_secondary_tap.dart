/// Coordinates Super Editor’s document right-click with embed field menus.
///
/// Embed [FormattedTextField]s handle secondary tap themselves. The document
/// [GestureDetector] is translucent and would otherwise open a second menu.
///
/// The gate stays set until [clearEmbedHandled] (menu close) — clearing on the
/// next frame let SE open a second menu that clobbered the frozen text mark.
abstract final class DocumentSecondaryTap {
  static bool _embedHandled = false;

  /// Call from an embed field before showing its context menu.
  static void markEmbedHandled() {
    _embedHandled = true;
  }

  /// Clear after the embed menu session finishes (or if no menu opened).
  static void clearEmbedHandled() {
    _embedHandled = false;
  }

  /// True when an embed field already consumed this secondary tap.
  static bool get embedHandled => _embedHandled;
}
