enum AppLanguage {
  en,
  he;

  static AppLanguage fromStorage(String? value) {
    return AppLanguage.values.firstWhere(
      (l) => l.name == value,
      orElse: () => AppLanguage.en,
    );
  }
}
