import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class ShortcutBinding {
  const ShortcutBinding({
    required this.keyId,
    this.meta = false,
    this.control = false,
    this.shift = false,
    this.alt = false,
  });

  final int keyId;
  final bool meta;
  final bool control;
  final bool shift;
  final bool alt;

  LogicalKeyboardKey get key => LogicalKeyboardKey(keyId);

  bool get isEmpty => keyId == 0;

  bool get hasModifier => meta || control || shift || alt;

  bool get isValid => keyId != 0 && (hasModifier || _isFunctionKey(key));

  static bool _isFunctionKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.f1 ||
        key == LogicalKeyboardKey.f2 ||
        key == LogicalKeyboardKey.f3 ||
        key == LogicalKeyboardKey.f4 ||
        key == LogicalKeyboardKey.f5 ||
        key == LogicalKeyboardKey.f6 ||
        key == LogicalKeyboardKey.f7 ||
        key == LogicalKeyboardKey.f8 ||
        key == LogicalKeyboardKey.f9 ||
        key == LogicalKeyboardKey.f10 ||
        key == LogicalKeyboardKey.f11 ||
        key == LogicalKeyboardKey.f12;
  }

  LogicalKeySet toLogicalKeySet() {
    final keys = <LogicalKeyboardKey>[];
    if (meta) keys.add(LogicalKeyboardKey.meta);
    if (control) keys.add(LogicalKeyboardKey.control);
    if (shift) keys.add(LogicalKeyboardKey.shift);
    if (alt) keys.add(LogicalKeyboardKey.alt);
    keys.add(key);
    return LogicalKeySet.fromSet(keys.toSet());
  }

  ShortcutActivator toActivator() => BindingShortcutActivator(this);

  Map<String, dynamic> toJson() => {
        'keyId': keyId,
        'meta': meta,
        'control': control,
        'shift': shift,
        'alt': alt,
      };

  factory ShortcutBinding.fromJson(Map<String, dynamic> json) {
    return ShortcutBinding(
      keyId: json['keyId'] as int? ?? 0,
      meta: json['meta'] as bool? ?? false,
      control: json['control'] as bool? ?? false,
      shift: json['shift'] as bool? ?? false,
      alt: json['alt'] as bool? ?? false,
    );
  }

  String displayLabel() {
    if (isEmpty) return '—';
    final parts = <String>[];
    final useMetaSymbol = !kIsWeb && Platform.isMacOS;
    if (meta) parts.add(useMetaSymbol ? '⌘' : 'Ctrl');
    if (control && !useMetaSymbol) parts.add('Ctrl');
    if (control && useMetaSymbol) parts.add('⌃');
    if (alt) parts.add(useMetaSymbol ? '⌥' : 'Alt');
    if (shift) parts.add(useMetaSymbol ? '⇧' : 'Shift');
    parts.add(_keyLabel(key));
    return parts.join(useMetaSymbol ? '' : '+');
  }

  static String _keyLabel(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.arrowLeft) return '←';
    if (key == LogicalKeyboardKey.arrowRight) return '→';
    if (key == LogicalKeyboardKey.arrowUp) return '↑';
    if (key == LogicalKeyboardKey.arrowDown) return '↓';
    if (key == LogicalKeyboardKey.bracketRight) return ']';
    if (key == LogicalKeyboardKey.bracketLeft) return '[';
    if (key == LogicalKeyboardKey.equal) return '=';
    if (key == LogicalKeyboardKey.minus) return '-';
    if (key == LogicalKeyboardKey.comma) return ',';
    if (key == LogicalKeyboardKey.period) return '.';
    if (key.keyLabel.length == 1) {
      return key.keyLabel.toUpperCase();
    }
    final id = key.keyId;
    if (id >= LogicalKeyboardKey.digit0.keyId &&
        id <= LogicalKeyboardKey.digit9.keyId) {
      return key.keyLabel;
    }
    if (id >= LogicalKeyboardKey.f1.keyId && id <= LogicalKeyboardKey.f12.keyId) {
      final offset = id - LogicalKeyboardKey.f1.keyId + 1;
      return 'F$offset';
    }
    return key.keyLabel.isNotEmpty ? key.keyLabel : (key.debugName ?? '?');
  }

  ShortcutBinding copyWith({
    int? keyId,
    bool? meta,
    bool? control,
    bool? shift,
    bool? alt,
  }) {
    return ShortcutBinding(
      keyId: keyId ?? this.keyId,
      meta: meta ?? this.meta,
      control: control ?? this.control,
      shift: shift ?? this.shift,
      alt: alt ?? this.alt,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ShortcutBinding &&
        other.keyId == keyId &&
        other.meta == meta &&
        other.control == control &&
        other.shift == shift &&
        other.alt == alt;
  }

  @override
  int get hashCode => Object.hash(keyId, meta, control, shift, alt);

  bool matchesEvent(KeyDownEvent event) => matchesHardware(event);

  /// True when this binding is the key that just went down (or is repeating).
  ///
  /// `Cmd+Shift+=` is often reported as the `+` key (`add` / numpad add), so
  /// those count as the same binding when this one is shift+equal.
  bool matchesHardware(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    final keyboard = HardwareKeyboard.instance;
    final key = event.logicalKey;
    final modifiersMatch = meta == keyboard.isMetaPressed &&
        control == keyboard.isControlPressed &&
        alt == keyboard.isAltPressed;
    if (!modifiersMatch) return false;
    if (key.keyId == keyId && shift == keyboard.isShiftPressed) return true;
    if (!shift) return false;
    if (keyId == LogicalKeyboardKey.equal.keyId) {
      return key == LogicalKeyboardKey.add ||
          key == LogicalKeyboardKey.numpadAdd;
    }
    if (keyId == LogicalKeyboardKey.minus.keyId) {
      final character = event.character;
      return key == LogicalKeyboardKey.underscore ||
          key == LogicalKeyboardKey.minus ||
          key == LogicalKeyboardKey.numpadSubtract ||
          character == '-' ||
          character == '_';
    }
    return false;
  }
}

/// [SingleActivator] misses `Cmd+Shift+-` when the platform reports `_`.
class BindingShortcutActivator extends ShortcutActivator {
  const BindingShortcutActivator(this.binding);

  final ShortcutBinding binding;

  @override
  bool accepts(KeyEvent event, HardwareKeyboard state) =>
      binding.matchesHardware(event);

  @override
  String debugDescribeKeys() => binding.displayLabel();

  @override
  Iterable<LogicalKeyboardKey> get triggers {
    final keys = <LogicalKeyboardKey>{binding.key};
    if (!binding.shift) return keys;
    if (binding.key == LogicalKeyboardKey.equal) {
      keys.addAll({LogicalKeyboardKey.add, LogicalKeyboardKey.numpadAdd});
    }
    if (binding.key == LogicalKeyboardKey.minus) {
      keys.addAll({
        LogicalKeyboardKey.underscore,
        LogicalKeyboardKey.numpadSubtract,
      });
    }
    return keys;
  }
}

ShortcutBinding? shortcutBindingFromEvent(KeyEvent event) {
  if (event is! KeyDownEvent) return null;
  final logical = event.logicalKey;
  if (logical == LogicalKeyboardKey.escape) return null;
  return ShortcutBinding(
    keyId: logical.keyId,
    meta: HardwareKeyboard.instance.isMetaPressed,
    control: HardwareKeyboard.instance.isControlPressed,
    shift: HardwareKeyboard.instance.isShiftPressed,
    alt: HardwareKeyboard.instance.isAltPressed,
  );
}
