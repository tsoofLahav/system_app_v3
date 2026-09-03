import './platform/app_form_factor.dart';

/// File-body size. Chrome (menus, sidebar) does not follow this.
enum DocumentTextSize {
  small,
  medium,
  large;

  /// Phone reads a step larger until the user picks a size.
  static DocumentTextSize get platformDefault =>
      isPhoneLayout ? medium : small;

  static DocumentTextSize fromStorage(String? value) {
    return DocumentTextSize.values.firstWhere(
      (size) => size.name == value,
      orElse: () => platformDefault,
    );
  }
}
