import 'package:flutter/widgets.dart';

/// Overlay anchors for chrome that other areas point at (hints, not layout).
abstract final class ChromeAnchors {
  static final preferencesButton = GlobalKey(debugLabel: 'preferencesButton');
}
