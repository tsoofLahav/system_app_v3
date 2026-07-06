import 'package:flutter/material.dart';

import '../models/topic.dart';

class TopicAppearance {
  static const String defaultColor = '#6B7280';
  static const String defaultEmoji = '📌';

  static const List<String> presetColors = [
    '#EF4444',
    '#F97316',
    '#F59E0B',
    '#84CC16',
    '#10B981',
    '#06B6D4',
    '#3B82F6',
    '#6366F1',
    '#8B5CF6',
    '#EC4899',
    '#6B7280',
    '#78716C',
    '#A855F7',
    '#14B8A6',
    '#F43F5E',
    '#0EA5E9',
  ];

  /// Legacy Material icon slug → emoji (topics created before emoji picker).
  static const Map<String, String> _legacyIconSlugs = {
    'home': '🏠',
    'house': '🏡',
    'work': '💼',
    'business': '🏢',
    'health': '💚',
    'heart': '❤️',
    'fitness': '💪',
    'restaurant': '🍽️',
    'coffee': '☕',
    'school': '🎓',
    'book': '📚',
    'palette': '🎨',
    'music': '🎵',
    'eco': '🌿',
    'pets': '🐾',
    'family': '👨‍👩‍👧',
    'travel': '✈️',
    'finance': '💰',
    'computer': '💻',
    'calendar': '📅',
    'star': '⭐',
    'flag': '🚩',
    'rocket': '🚀',
    'folder': '📁',
  };

  static String emojiFromId(String? value) {
    if (value == null || value.isEmpty) return defaultEmoji;
    final legacy = _legacyIconSlugs[value];
    if (legacy != null) return legacy;
    if (_looksLikeEmoji(value)) return value;
    return defaultEmoji;
  }

  static bool _looksLikeEmoji(String value) {
    if (value.contains(RegExp(r'^[a-z0-9_]+$'))) return false;
    return true;
  }

  static Color colorFromHex(String? hex) {
    if (hex == null || hex.isEmpty) return const Color(0xFF6B7280);
    var v = hex.replaceFirst('#', '');
    if (v.length == 6) v = 'FF$v';
    return Color(int.parse(v, radix: 16));
  }

  /// Topic tint for glass/file chrome. Main topic stays white like its panes.
  static Color accentFor(Topic topic) {
    if (topic.isMain) return Colors.white;
    return colorFromHex(topic.color);
  }

  static String hexFromColor(Color color) {
    final argb = color.toARGB32();
    return '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }
}
