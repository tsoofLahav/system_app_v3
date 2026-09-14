import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'paragraph_text_direction.dart';

/// A preference changes layout, never the stored text or the input value.
enum TextDirectionPolicy { firstStrong, appLanguage }

abstract final class WritingDirection {
  static final policy = ValueNotifier(TextDirectionPolicy.firstStrong);

  static TextDirection resolve(String text, TextDirection ambient) =>
      policy.value == TextDirectionPolicy.appLanguage
      ? ambient
      : detectParagraphTextDirection(text) ?? ambient;
}
