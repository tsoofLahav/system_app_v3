import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// True on native iOS (including iPad for v1).
bool get isPhoneLayout => !kIsWeb && Platform.isIOS;

/// Phone (native iOS, including tests that override the target platform):
/// enlarge a mark with handles only — a body drag scrolls or swipes files.
bool get phoneMarksWithHandlesOnly =>
    isPhoneLayout || defaultTargetPlatform == TargetPlatform.iOS;
