/// Image object payload: one picture, or a row of panes.
class ImageObjectPayload {
  ImageObjectPayload._();

  static List<Map<String, String>> panesOf(Map<String, dynamic>? payload) {
    final raw = payload ?? const <String, dynamic>{};
    final images = raw['images'];
    if (images is List && images.isNotEmpty) {
      final panes = <Map<String, String>>[];
      for (final item in images) {
        if (item is! Map) continue;
        panes.add({
          'url': '${item['url'] ?? item['path'] ?? ''}'.trim(),
          'caption': '${item['caption'] ?? ''}',
        });
      }
      if (panes.isNotEmpty) return panes;
    }
    return [
      {
        'url': '${raw['url'] ?? raw['path'] ?? ''}'.trim(),
        'caption': '${raw['caption'] ?? ''}',
      },
    ];
  }

  /// First pane is also mirrored on [url] / [caption] for older readers.
  static Map<String, dynamic> mirrored(
    List<Map<String, String>> panes, {
    Map<String, dynamic>? existing,
  }) {
    final cleaned = [
      for (final p in panes)
        {
          'url': (p['url'] ?? '').trim(),
          'caption': p['caption'] ?? '',
        },
    ];
    if (cleaned.isEmpty) {
      cleaned.add({'url': '', 'caption': ''});
    }
    final first = cleaned.first;
    final out = <String, dynamic>{
      ...?existing,
      'url': first['url'],
      'caption': first['caption'],
    };
    if (cleaned.length > 1) {
      out['images'] = cleaned;
    } else {
      out.remove('images');
    }
    return out;
  }

  static Map<String, dynamic> merge(
    Map<String, dynamic>? keeper,
    Map<String, dynamic>? absorbed,
  ) {
    return mirrored(
      [...panesOf(keeper), ...panesOf(absorbed)],
      existing: keeper,
    );
  }
}
