import 'package:flutter/material.dart';

/// Default column labels for new graph blocks.
const kDefaultGraphLabels = ['A', 'B', 'C'];

/// Soft pastel palettes (ARGB32) for graph columns.
const kGraphColorPalettes = <List<int>>[
  [0xFF7EB8DA, 0xFF9BC9A8, 0xFFE8C07A, 0xFFC9A8D8, 0xFFE8A8A8, 0xFFA8C9E8],
  [0xFF6BAED6, 0xFF74C476, 0xFFFDD089, 0xFFBC80BD, 0xFFFB8072, 0xFF80B1D3],
  [0xFF9D988F, 0xFFB5B0A6, 0xFFCEC9BF, 0xFF878279, 0xFFDCD8CF, 0xFF6E6A62],
];

Map<String, dynamic> defaultGraphContent() => {
  'chart_type': 'bar',
  'title': '',
  'labels': List<String>.from(kDefaultGraphLabels),
  'values': <double>[0, 0, 0],
  'palette_index': 0,
};

List<String> graphLabels(Map<String, dynamic> content) {
  final raw = content['labels'];
  if (raw is List && raw.isNotEmpty) {
    return [for (final item in raw) item.toString()];
  }
  return List<String>.from(kDefaultGraphLabels);
}

List<double> graphValues(Map<String, dynamic> content, int labelCount) {
  final raw = content['values'];
  final values = <double>[];
  if (raw is List) {
    for (final item in raw) {
      if (item is num) {
        values.add(item.toDouble());
      } else {
        values.add(double.tryParse(item.toString()) ?? 0);
      }
    }
  }
  while (values.length < labelCount) {
    values.add(0);
  }
  if (values.length > labelCount) {
    values.removeRange(labelCount, values.length);
  }
  return values;
}

int graphPaletteIndex(Map<String, dynamic> content) {
  final index = content['palette_index'];
  if (index is int && index >= 0) return index % kGraphColorPalettes.length;
  return 0;
}

List<Color> graphColumnColors(Map<String, dynamic> content, int count) {
  final explicit = content['colors'];
  if (explicit is List && explicit.length >= count) {
    return [
      for (var i = 0; i < count; i++)
        _colorFromStored(explicit[i]),
    ];
  }
  final palette = kGraphColorPalettes[graphPaletteIndex(content)];
  return [
    for (var i = 0; i < count; i++) Color(palette[i % palette.length]),
  ];
}

Color _colorFromStored(Object? value) {
  if (value is int) return Color(value);
  if (value is String && value.startsWith('#')) {
    final hex = value.substring(1);
    final parsed = int.tryParse(hex, radix: 16);
    if (parsed != null) {
      return Color(hex.length <= 6 ? 0xFF000000 | parsed : parsed);
    }
  }
  return const Color(0xFF7EB8DA);
}

String nextGraphLabel(List<String> labels) {
  final index = labels.length;
  if (index < 26) return String.fromCharCode(65 + index);
  return 'V$index';
}

Map<String, dynamic> graphContentWithColumns({
  required Map<String, dynamic> base,
  required List<String> labels,
  required List<double> values,
}) {
  return {
    ...base,
    'labels': labels,
    'values': values,
    'colors': null,
  };
}

int nextGraphPaletteIndex(Map<String, dynamic> content) =>
    (graphPaletteIndex(content) + 1) % kGraphColorPalettes.length;

final _isoDatePattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
final _shortDatePattern = RegExp(r'^(\d{2})-(\d{2})$');

/// Chart axis label: drop the year for ISO dates, keep everything else as-is.
String graphAxisLabel(String label) {
  final trimmed = label.trim();
  final iso = _isoDatePattern.firstMatch(trimmed);
  if (iso != null) {
    return '${iso.group(2)}-${iso.group(3)}';
  }
  return trimmed;
}

/// Canonical day key for duplicate detection. Non-date labels return null.
String? graphDayKey(String label, {int? referenceYear}) {
  final trimmed = label.trim();
  final iso = _isoDatePattern.firstMatch(trimmed);
  if (iso != null) {
    return '${iso.group(1)}-${iso.group(2)}-${iso.group(3)}';
  }
  final short = _shortDatePattern.firstMatch(trimmed);
  if (short != null) {
    final year = referenceYear ?? DateTime.now().year;
    return '$year-${short.group(1)}-${short.group(2)}';
  }
  return null;
}

bool graphDayKeyConflicts(
  List<String> labels,
  int index,
  String candidate, {
  int? referenceYear,
}) {
  final key = graphDayKey(candidate, referenceYear: referenceYear);
  if (key == null) return false;
  for (var i = 0; i < labels.length; i++) {
    if (i == index) continue;
    final other = graphDayKey(labels[i], referenceYear: referenceYear);
    if (other != null && other == key) return true;
  }
  return false;
}
