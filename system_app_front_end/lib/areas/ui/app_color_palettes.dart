/// Named colour sets for charts and similar multi-series UI.
///
/// Flutter has no built-in chart-palette picker — these are the app's curated
/// options. Each palette has **8** distinct colours (the graph column limit).
class AppColorPalette {
  const AppColorPalette({
    required this.id,
    required this.nameKey,
    required this.hexes,
  });

  final String id;

  /// Key in [AppStrings] for the display name.
  final String nameKey;

  /// Exactly [AppColorPalettes.seriesLimit] hex colours.
  final List<String> hexes;

  /// One colour per series index (cycles only if count exceeds [hexes]).
  List<String> colorsForCount(int count) {
    if (count <= 0) return const [];
    if (hexes.isEmpty) return List.filled(count, '#37899E');
    return [for (var i = 0; i < count; i++) hexes[i % hexes.length]];
  }
}

abstract final class AppColorPalettes {
  /// Max series / graph variables — matches palette length.
  static const seriesLimit = 8;

  static const List<AppColorPalette> chart = [
    AppColorPalette(
      id: 'teal',
      nameKey: 'paletteTeal',
      hexes: [
        '#1E5A68',
        '#2A6A7A',
        '#37899E',
        '#51A0B0',
        '#58C4D8',
        '#7DD3E0',
        '#A8E0EA',
        '#C5EEF4',
      ],
    ),
    AppColorPalette(
      id: 'warm',
      nameKey: 'paletteWarm',
      hexes: [
        '#8B4513',
        '#B45309',
        '#C45C26',
        '#D97757',
        '#E0A04A',
        '#E8B86D',
        '#F0C987',
        '#F6DDB0',
      ],
    ),
    AppColorPalette(
      id: 'cool',
      nameKey: 'paletteCool',
      hexes: [
        '#2F5D7A',
        '#3B6FA0',
        '#4A90A4',
        '#5B8FA8',
        '#6B7C9E',
        '#7BA3C9',
        '#8FB4D4',
        '#A8C8E0',
      ],
    ),
    AppColorPalette(
      id: 'bright',
      nameKey: 'paletteBright',
      hexes: [
        '#E53935',
        '#FB8C00',
        '#FDD835',
        '#43A047',
        '#00ACC1',
        '#1E88E5',
        '#5E35B1',
        '#8E24AA',
      ],
    ),
    AppColorPalette(
      id: 'muted',
      nameKey: 'paletteMuted',
      hexes: [
        '#6E7A72',
        '#7D8A8F',
        '#8A847A',
        '#9A8B7A',
        '#A89F91',
        '#B0A89C',
        '#C0B8AC',
        '#D0C8BC',
      ],
    ),
    AppColorPalette(
      id: 'forest',
      nameKey: 'paletteForest',
      hexes: [
        '#1F4D38',
        '#2F6B4F',
        '#3D7A5A',
        '#5F8F5B',
        '#6F9E5F',
        '#8FAE6E',
        '#A3C18B',
        '#C0D4A8',
      ],
    ),
    AppColorPalette(
      id: 'sunset',
      nameKey: 'paletteSunset',
      hexes: [
        '#8E3B5B',
        '#C23B4A',
        '#D94F30',
        '#E07040',
        '#E89B3C',
        '#F0C35E',
        '#F5A26B',
        '#F8C89A',
      ],
    ),
  ];

  static AppColorPalette? byId(String id) {
    for (final p in chart) {
      if (p.id == id) return p;
    }
    return null;
  }

  static AppColorPalette get defaultChart => chart.first;
}
