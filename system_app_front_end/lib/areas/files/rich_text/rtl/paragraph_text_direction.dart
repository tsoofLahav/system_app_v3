/// Paragraph base direction — part of the [RTL solution](RTL.md).
///
/// First strong directional character (Unicode P2/P3 style). Neutral-only or
/// empty text returns null — caller uses ambient UI [Directionality].
/// Prefer [resolveFieldTextDirection] from `rtl.dart` at call sites.
library;

import 'package:flutter/painting.dart';

/// Base direction from the first strong LTR/RTL character, or null if none.
TextDirection? detectParagraphTextDirection(String text) {
  for (final code in text.runes) {
    if (_isStrongRtl(code)) return TextDirection.rtl;
    if (_isStrongLtr(code)) return TextDirection.ltr;
  }
  return null;
}

bool _isStrongRtl(int code) {
  return (code >= 0x0590 && code <= 0x05FF) || // Hebrew
      (code >= 0x0600 && code <= 0x06FF) || // Arabic
      (code >= 0x0700 && code <= 0x074F) || // Syriac
      (code >= 0x0750 && code <= 0x077F) || // Arabic Supplement
      (code >= 0x0780 && code <= 0x07BF) || // Thaana
      (code >= 0x07C0 && code <= 0x07FF) || // NKo
      (code >= 0x0800 && code <= 0x083F) || // Samaritan
      (code >= 0x08A0 && code <= 0x08FF) || // Arabic Extended-A
      (code >= 0xFB1D && code <= 0xFDFF) || // Alphabetic Presentation Forms…
      (code >= 0xFE70 && code <= 0xFEFF); // Arabic Presentation Forms-B
}

bool _isStrongLtr(int code) {
  return (code >= 0x0041 && code <= 0x005A) || // A-Z
      (code >= 0x0061 && code <= 0x007A) || // a-z
      (code >= 0x00C0 && code <= 0x00D6) ||
      (code >= 0x00D8 && code <= 0x00F6) ||
      (code >= 0x00F8 && code <= 0x02B8) ||
      (code >= 0x0400 && code <= 0x0482) || // Cyrillic
      (code >= 0x048A && code <= 0x052F) ||
      (code >= 0x0370 && code <= 0x03FF) || // Greek
      (code >= 0x1E00 && code <= 0x1EFF); // Latin Extended Additional
}
