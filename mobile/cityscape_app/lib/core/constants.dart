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

/// Clé des favoris dans les préférences locales.
///
/// Les favoris ne vivent que sur l'appareil et ne sont jamais transmis au
/// serveur. Déclarée ici parce que deux endroits en dépendent : la liste des
/// escapes, qui les lit et les écrit, et la déconnexion, qui doit les effacer
/// — sans quoi le joueur suivant sur un téléphone partagé verrait les favoris
/// du précédent.
const String kFavorisKey = 'fav_ids';

// Asset du logo (déclaré dans pubspec.yaml)
const String kLogoAsset = 'assets/logo.png';
