import 'package:characters/characters.dart';
import 'package:flutter/services.dart';

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

/// Snaps a selection start out of the middle of a grapheme (emoji, ZWJ, …).
int normalizeUtf16Start(String text, int offset) {
  final pos = offset.clamp(0, text.length);
  if (pos <= 0 || pos >= text.length) return pos;
  var i = 0;
  for (final g in text.characters) {
    final next = i + g.length;
    if (pos <= i) return pos;
    if (pos < next) return i;
    i = next;
  }
  return pos;
}

/// Snaps a selection end out of the middle of a grapheme (emoji, ZWJ, …).
int normalizeUtf16End(String text, int offset) {
  final pos = offset.clamp(0, text.length);
  if (pos <= 0 || pos >= text.length) return pos;
  var i = 0;
  for (final g in text.characters) {
    final next = i + g.length;
    if (pos <= i) return pos;
    if (pos < next) return next;
    i = next;
  }
  return pos;
}

(int, int) normalizeUtf16Range(String text, int start, int end) {
  var rangeStart = start.clamp(0, text.length);
  var rangeEnd = end.clamp(0, text.length);
  if (rangeEnd < rangeStart) {
    final swap = rangeStart;
    rangeStart = rangeEnd;
    rangeEnd = swap;
  }
  rangeStart = normalizeUtf16Start(text, rangeStart);
  rangeEnd = normalizeUtf16End(text, rangeEnd);
  if (rangeEnd < rangeStart) rangeEnd = rangeStart;
  return (rangeStart, rangeEnd);
}

TextSelection normalizeTextSelection(String text, TextSelection selection) {
  if (!selection.isValid) return selection;
  if (selection.isCollapsed) {
    final caret = normalizeUtf16End(text, selection.extentOffset);
    if (caret == selection.baseOffset && caret == selection.extentOffset) {
      return selection;
    }
    return TextSelection.collapsed(offset: caret, affinity: selection.affinity);
  }
  final (start, end) = normalizeUtf16Range(
    text,
    selection.start,
    selection.end,
  );
  final forward = selection.baseOffset <= selection.extentOffset;
  final base = forward ? start : end;
  final extent = forward ? end : start;
  if (base == selection.baseOffset && extent == selection.extentOffset) {
    return selection;
  }
  return TextSelection(
    baseOffset: base,
    extentOffset: extent,
    affinity: selection.affinity,
  );
}

String safeSubstring(String text, int start, int end) {
  final (rangeStart, rangeEnd) = normalizeUtf16Range(text, start, end);
  if (rangeEnd <= rangeStart) return '';
  return sanitizePlatformText(text.substring(rangeStart, rangeEnd));
}

/// One grapheme before [offset], or 0. Used by Shift+arrows so a mark
/// cannot land between the two UTF-16 units of an emoji.
int graphemeOffsetBefore(String text, int offset) {
  final pos = offset.clamp(0, text.length);
  if (pos <= 0) return 0;
  return normalizeUtf16Start(text, pos - 1);
}

/// One grapheme after [offset], or [text.length].
int graphemeOffsetAfter(String text, int offset) {
  final pos = offset.clamp(0, text.length);
  if (pos >= text.length) return text.length;
  return normalizeUtf16End(text, pos + 1);
}

Future<void> setClipboardText(String text) async {
  final safe = sanitizePlatformText(text);
  if (safe.isEmpty) return;
  await Clipboard.setData(ClipboardData(text: safe));
}

Future<String?> getClipboardText() async {
  final data = await Clipboard.getData(Clipboard.kTextPlain);
  final text = data?.text;
  if (text == null) return null;
  final safe = sanitizePlatformText(text);
  return safe.isEmpty ? null : safe;
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
