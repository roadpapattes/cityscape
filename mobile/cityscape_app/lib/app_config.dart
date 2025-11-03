class AppConfig {
  // Valeur par défaut = dev local (Android émulateur)
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );
}