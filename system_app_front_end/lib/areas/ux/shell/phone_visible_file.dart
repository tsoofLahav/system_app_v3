import 'package:flutter/foundation.dart';
import '../../files/data/topic.dart';

/// The file currently on the phone swipe page — chrome only.
///
/// Do not put this on [AppState]. The topic canvas must not rebuild on swipe.
class PhoneVisibleFile {
  PhoneVisibleFile._();

  static final ValueNotifier<String?> name = ValueNotifier<String?>(null);

  static final source = ValueNotifier<Topic?>(null);
  static Topic? get sourceTopic => source.value;

  static void setName(String? next, {Topic? source}) {
    PhoneVisibleFile.source.value = source;
    if (name.value == next) return;
    name.value = next;
  }
}
