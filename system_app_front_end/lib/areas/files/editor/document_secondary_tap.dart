/// Coordinates Super Editor’s document right-click with embed field menus.
///
/// Embed [FormattedTextField]s handle secondary tap themselves. The document
/// [GestureDetector] is translucent and would otherwise open a second menu
/// for the **same** pointer.
///
/// The gate is per pointer: a new right-click (body or another field) is not
/// swallowed by a menu that is still open from the previous click.
abstract final class DocumentSecondaryTap {
  static int? _pointer;
  static var _embedHandled = false;

  /// Start of a secondary pointer. Resets the gate when the pointer is new.
  static void notePointer(int pointer) {
    if (_pointer == pointer) return;
    _pointer = pointer;
    _embedHandled = false;
  }

  /// Call from an embed field before showing its context menu.
  static void markEmbedHandled() {
    _embedHandled = true;
  }

  /// Clear after the embed menu session finishes (or if no menu opened).
  static void clearEmbedHandled() {
    _embedHandled = false;
    _pointer = null;
  }

  /// True when an embed field already consumed **this** secondary pointer.
  static bool get embedHandled => _embedHandled;
}
