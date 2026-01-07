// lib/core/constants.dart

/// Emulateur Android classique => 10.0.2.2
/// (Si tu fais `adb reverse tcp:8000 tcp:8000`, bascule en 127.0.0.1)
const String baseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://api.cityscape.ovh',
);

const String kEngagementPrefix = ""; // sessions, hints, answers, rating
const String kAuthPrefix = ""; // auth stays at /api/auth/...
const double kDefaultRadiusKm = 20;

// Asset du logo (déclaré dans pubspec.yaml)
const String kLogoAsset = 'assets/logo.png';
