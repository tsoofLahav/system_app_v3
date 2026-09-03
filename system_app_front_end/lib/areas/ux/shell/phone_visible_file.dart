import 'package:flutter/foundation.dart';

/// The file currently on the phone swipe page — chrome only.
///
/// Do not put this on [AppState]. The topic canvas must not rebuild on swipe.
class PhoneVisibleFile {
  PhoneVisibleFile._();

  static final ValueNotifier<String?> name = ValueNotifier<String?>(null);

  static void setName(String? next) {
    if (name.value == next) return;
    name.value = next;
  }
}
