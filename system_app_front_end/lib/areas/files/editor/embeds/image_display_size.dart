/// Display width of an in-file image, as a fraction of the file pane.
///
/// Aspect ratio is kept by laying out at this width with [BoxFit.contain].
/// Missing / invalid / legacy pixel values read as full width.
abstract final class ImageDisplaySize {
  static const tiny = 0.125;
  static const quarter = 0.25;
  static const half = 0.5;
  static const full = 1.0;
  static const step = 0.1;

  static double scaleOf(Map<String, dynamic>? payload) {
    final raw = payload?['width'];
    if (raw is! num) return full;
    final value = raw.toDouble();
    if (value <= 0 || value > 1) return full;
    return value.clamp(tiny, full);
  }

  static double normalize(double scale) {
    final clamped = scale.clamp(tiny, full);
    return (clamped * 1000).round() / 1000;
  }

  static bool matchesNamed(double scale, double named) =>
      (scale - named).abs() < 0.02;

  static Map<String, dynamic> withScale(
    Map<String, dynamic>? payload,
    double scale,
  ) {
    return {...?payload, 'width': normalize(scale)};
  }

  static Map<String, dynamic>? apply(
    String action,
    Map<String, dynamic>? payload,
  ) {
    final current = scaleOf(payload);
    switch (action) {
      case 'image:smaller':
        return withScale(payload, current - step);
      case 'image:larger':
        return withScale(payload, current + step);
      case 'image:size:tiny':
        return withScale(payload, tiny);
      case 'image:size:quarter':
        return withScale(payload, quarter);
      case 'image:size:half':
        return withScale(payload, half);
      case 'image:size:full':
        return withScale(payload, full);
      default:
        return null;
    }
  }
}
