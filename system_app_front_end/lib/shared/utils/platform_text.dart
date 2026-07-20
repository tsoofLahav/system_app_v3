import 'package:characters/characters.dart';

/// Removes unpaired UTF-16 surrogates so Flutter platform channels can encode text.
String sanitizePlatformText(String input) {
  if (input.isEmpty) return input;

  final units = input.codeUnits;
  final out = <int>[];
  for (var i = 0; i < units.length; i++) {
    final unit = units[i];
    if (unit >= 0xD800 && unit <= 0xDBFF) {
      if (i + 1 < units.length) {
        final next = units[i + 1];
        if (next >= 0xDC00 && next <= 0xDFFF) {
          out
            ..add(unit)
            ..add(next);
          i++;
          continue;
        }
      }
      continue;
    }
    if (unit >= 0xDC00 && unit <= 0xDFFF) {
      continue;
    }
    out.add(unit);
  }
  return String.fromCharCodes(out);
}

bool looksLikeEmojiGrapheme(String grapheme) {
  if (grapheme.isEmpty) return false;
  for (final rune in grapheme.runes) {
    if (rune == 0x200D || rune == 0xFE0F) continue;
    if (rune >= 0x1F1E6 && rune <= 0x1F1FF) continue;
    if (rune >= 0x1F300 && rune <= 0x1FAFF) continue;
    if (rune >= 0x1F600 && rune <= 0x1F64F) continue;
    if (rune >= 0x1F680 && rune <= 0x1F6FF) continue;
    if (rune >= 0x1F900 && rune <= 0x1F9FF) continue;
    if (rune >= 0x2600 && rune <= 0x27BF) continue;
    if (rune >= 0x231A && rune <= 0x23FA) continue;
    if (rune >= 0x25AA && rune <= 0x25FE) continue;
    if (rune == 0x25B6 || rune == 0x25C0) continue;
    if (rune == 0x3297 || rune == 0x3299) continue;
    return false;
  }
  return true;
}

/// Keeps up to [maxCount] emoji graphemes from an AI emoji reply.
String? insertableEmojis(String raw, {int maxCount = 2}) {
  final clean = sanitizePlatformText(raw.trim());
  if (clean.isEmpty || maxCount < 1) return null;

  final parts = <String>[];
  for (final grapheme in clean.characters) {
    final token = sanitizePlatformText(grapheme.trim());
    if (token.isEmpty) continue;
    if (!looksLikeEmojiGrapheme(token)) break;
    parts.add(token);
    if (parts.length >= maxCount) break;
  }

  if (parts.isEmpty) return null;
  return parts.join();
}
