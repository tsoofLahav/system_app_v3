import '../../ui/app_color_palettes.dart';

/// Canonical table object payload: [rows] grid + optional [chart] quality.
///
/// Chart tables are still `objects.type = table`; insert “graph” is sugar that
/// turns [chart.enabled] on with a default 2×N grid.
class TableObjectPayload {
  TableObjectPayload._();

  static const defaultChartType = 'bar';

  static Map<String, dynamic> empty({int columns = 2}) => {
        'rows': [
          [
            for (var c = 0; c < columns; c++) {'text': ''},
          ],
        ],
      };

  /// Default chart table (former graph insert).
  ///
  /// When [hebrewLabels] is true (UI RTL / Hebrew mode), series labels use
  /// א, ב, … instead of A, B, ….
  static Map<String, dynamic> emptyChart({
    int columns = 2,
    bool hebrewLabels = false,
  }) {
    final hexes = AppColorPalettes.defaultChart.hexes;
    return {
      'rows': [
        [
          for (var c = 0; c < columns; c++)
            {
              'text': hebrewLabels
                  ? String.fromCharCode(0x05D0 + c) // א, ב, …
                  : String.fromCharCode(0x41 + c), // A, B, …
            },
        ],
        [
          for (var c = 0; c < columns; c++) {'text': '${c + 1}'},
        ],
      ],
      'chart': {
        'enabled': true,
        'chartType': defaultChartType,
        'colors': [
          for (var c = 0; c < columns; c++) hexes[c % hexes.length],
        ],
      },
    };
  }

  static Map<String, dynamic> fromRowStrings(List<List<String>> rows) => {
        'rows': [
          for (final row in rows)
            [
              for (final cell in row) {'text': cell},
            ],
        ],
      };

  static bool chartEnabled(Map<String, dynamic>? payload) {
    if (payload == null) return false;
    final chart = payload['chart'];
    if (chart is Map && chart['enabled'] == true) return true;
    // Legacy graph shape.
    return payload.containsKey('labels') || payload.containsKey('values');
  }

  /// Accept rows, or legacy labels/values → rows + chart.
  static Map<String, dynamic> normalize(Map<String, dynamic>? payload) {
    final raw = payload == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(payload);

    if (raw['rows'] is List) {
      final rows = _normalizeRows(raw['rows'] as List);
      final out = <String, dynamic>{'rows': rows};
      final chart = raw['chart'];
      if (chart is Map) {
        out['chart'] = _normalizeChart(
          Map<String, dynamic>.from(chart),
          columnCount: rows.isEmpty ? 2 : (rows.first as List).length,
        );
      }
      return out;
    }

    final labels = _stringList(raw['labels']);
    final values = _stringList(raw['values']);
    var colors = _stringList(raw['colors']);
    if (colors.isEmpty && raw['color'] != null) {
      colors = ['${raw['color']}'];
    }
    final chartType =
        '${raw['chartType'] ?? raw['chart_type'] ?? defaultChartType}'.trim();
    final n = [labels.length, values.length, colors.length, 2]
        .reduce((a, b) => a > b ? a : b);
    final lab = [...labels, ...List.filled(n, '')].take(n).toList();
    final val = [...values, ...List.filled(n, '')].take(n).toList();
    final cols = colors.isEmpty
        ? <String>[]
        : [...colors, ...List.filled(n, '')].take(n).toList();

    return {
      'rows': [
        [
          for (final t in lab) {'text': t},
        ],
        [
          for (final t in val) {'text': t},
        ],
      ],
      'chart': {
        'enabled': true,
        'chartType': chartType.isEmpty ? defaultChartType : chartType,
        'colors': cols,
      },
    };
  }

  static List<List<Map<String, dynamic>>> rowsOf(Map<String, dynamic> payload) {
    final n = normalize(payload);
    final raw = n['rows'] as List;
    return [
      for (final row in raw)
        if (row is List)
          [
            for (final cell in row)
              {
                'text': cell is Map ? '${cell['text'] ?? ''}' : '$cell',
              },
          ],
    ];
  }

  static Map<String, dynamic>? chartOf(Map<String, dynamic>? payload) {
    final n = normalize(payload);
    final chart = n['chart'];
    if (chart is! Map) return null;
    return Map<String, dynamic>.from(chart);
  }

  /// Marker / agent tag preference: chart-on → graph, else table.
  static String pointerObjectType(Map<String, dynamic>? payload) =>
      chartEnabled(payload) ? 'graph' : 'table';

  static List<String> _stringList(dynamic raw) {
    if (raw is! List) return [];
    return [for (final x in raw) '$x'];
  }

  static List<List<Map<String, dynamic>>> _normalizeRows(List rows) {
    final parsed = <List<Map<String, dynamic>>>[];
    for (final row in rows) {
      if (row is! List) continue;
      parsed.add([
        for (final cell in row)
          {
            'text': cell is Map ? '${cell['text'] ?? ''}' : '$cell',
          },
      ]);
    }
    if (parsed.isEmpty) {
      return [
        [
          {'text': ''},
          {'text': ''},
        ],
      ];
    }
    final maxCols = parsed.map((r) => r.length).reduce((a, b) => a > b ? a : b);
    final cols = maxCols < 1 ? 2 : maxCols;
    return [
      for (final row in parsed)
        [
          for (var c = 0; c < cols; c++)
            c < row.length ? row[c] : {'text': ''},
        ],
    ];
  }

  static Map<String, dynamic> _normalizeChart(
    Map<String, dynamic> chart, {
    required int columnCount,
  }) {
    final colorsRaw = chart['colors'];
    final colors = colorsRaw is List
        ? [for (final c in colorsRaw) '$c']
        : <String>[];
    final type =
        '${chart['chartType'] ?? chart['chart_type'] ?? defaultChartType}'
            .trim();
    return {
      'enabled': chart['enabled'] != false,
      'chartType': type.isEmpty ? defaultChartType : type,
      'colors': colors,
    };
  }
}
