import './platform/app_form_factor.dart';

/// File-body size in points. Chrome (menus, sidebar) does not follow this.
///
/// Preferences lists every step so the user can match a size, not only
/// Small / Medium / Large. Stored names `small` / `medium` / `large` still
/// load as 12.5 / 14 / 16.
enum DocumentTextSize {
  pt12(12),
  pt12_5(12.5),
  pt13(13),
  pt13_5(13.5),
  pt14(14),
  pt14_5(14.5),
  pt15(15),
  pt16(16),
  pt17(17),
  pt18(18);

  const DocumentTextSize(this.points);

  final double points;

  /// Phone reads a step larger until the user picks a size.
  static DocumentTextSize get platformDefault =>
      isPhoneLayout ? pt14 : pt12_5;

  String get label {
    final n = points;
    return n == n.roundToDouble() ? '${n.toInt()}' : '$n';
  }

  static DocumentTextSize fromStorage(String? value) {
    switch (value) {
      case 'small':
        return pt12_5;
      case 'medium':
        return pt14;
      case 'large':
        return pt16;
    }
    for (final size in DocumentTextSize.values) {
      if (size.name == value) return size;
    }
    return platformDefault;
  }
}
