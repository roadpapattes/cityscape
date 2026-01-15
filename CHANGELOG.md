# Changelog CityScape

## Version 0.2.1 (2025-01-15)

### 🚀 Nouvelles fonctionnalités majeures

#### Application Mobile
- **Système de mise à jour forcée**: Vérification de version au démarrage avec dialog bloquante si mise à jour requise
- **Thèmes UI personnalisables**: 3 styles visuels (Card Collection, Gaming UI, Playful) sélectionnables dans le profil
- **AppBar et BottomNav thématisés**: Navigation visuelle qui s'adapte au style choisi
- **Amélioration majeure de l'interface carte**:
  - Marqueurs personnalisés avec gradients et badges
  - Bottom sheet animé pour les détails des escapes
  - Filtres (difficulté, note, favoris)
  - Cercle de rayon de recherche
  - Toggle mode sombre

#### Backend
- **Endpoint `/api/app-config`**: Configuration de version pour forcer les mises à jour
- **Pages web statiques**:
  - Page d'accueil `/` avec redirection Play Store
  - Page `/downloads/` pour rediriger les anciens liens APK
- **Script de déploiement automatisé** (`deploy.sh`)

#### Interface Web React (nouveau!)
- **Application web complète** pour créer et gérer des escapes
- Dashboard avec liste des escapes (brouillon, soumis, publié, rejeté)
- Éditeur d'escape avec:
  - Informations générales (titre, ville, coordonnées)
  - Gestion complète des étapes
  - 5 types d'énigmes supportés
  - Système d'indices avec pénalités
  - Géolocalisation par étape
  - Réordonnancement drag & drop
- Authentification par token
- Interface moderne avec thème violet

### 🔧 Améliorations techniques

#### Mobile
- Service `VersionCheckService` pour vérifier la version de l'app
- Widget `UpdateRequiredDialog` pour bloquer l'app si obsolète
- Service `PreferencesService` étendu avec `ChangeNotifier` pour réactivité
- Service `FavoritesService` pour gérer les favoris localement
- Générateur de marqueurs personnalisés (`CustomMarkerGenerator`)
- Version mobile: 0.2.1 (versionCode 4)

#### Backend
- Amélioration de l'interface admin Django
- Nouvelles routes pour pages statiques
- Configuration pour servir l'interface React

### 🐛 Corrections
- Correction de l'intégration `AuthService` dans la page profil
- Suppression des références email inexistantes dans `UserMe`
- Ajout de `dart:math` manquant pour les marqueurs
- Correction des versions dans `build.gradle.kts`

### 📦 Fichiers ajoutés
- `mobile/cityscape_app/lib/services/version_check_service.dart`
- `mobile/cityscape_app/lib/core/widgets/update_required_dialog.dart`
- `mobile/cityscape_app/lib/core/widgets/themed_app_bar.dart`
- `mobile/cityscape_app/lib/core/widgets/themed_bottom_nav.dart`
- `mobile/cityscape_app/lib/features/map/widgets/custom_marker_painter.dart`
- `mobile/cityscape_app/lib/features/map/widgets/escape_bottom_sheet.dart`
- `mobile/cityscape_app/lib/features/map/widgets/map_filters.dart`
- `mobile/cityscape_app/lib/services/favorites_service.dart`
- `mobile/cityscape_app/lib/models/user_preferences.dart`
- `mobile/cityscape_app/lib/services/preferences_service.dart`
- `mobile/cityscape_app/lib/features/list/widgets/card_collection_style.dart`
- `mobile/cityscape_app/lib/features/list/widgets/gaming_ui_style.dart`
- `mobile/cityscape_app/lib/features/list/widgets/playful_style.dart`
- `mobile/cityscape_app/lib/features/profile/profile_page.dart`
- `static_html/index.html`
- `static_html/downloads.html`
- `deploy.sh`
- `creator-web/` (application React complète - 20 fichiers)

### 📝 Notes de déploiement

#### Pour activer la mise à jour forcée:
1. Déployer la nouvelle version sur le Play Store
2. Modifier `/api/app-config` dans `backend/urls.py`:
   ```python
   "min_version": "0.2.1",
   "force_update": True
   ```
3. Redémarrer le backend

#### Pour déployer le backend:
```bash
./deploy.sh
```

#### Pour déployer l'interface React:
```bash
cd creator-web
npm install
npm run build
# Copier dist/ vers le serveur
```

---

## Version 0.2.0 (2025-01-14)

### 🚀 Fonctionnalités
- Amélioration de l'interface mobile
- Styles de cartes personnalisables
- Interface admin Django complète

### 🐛 Corrections
- Divers bugs corrigés

---

## Version 0.1.0 (2025-01-13)

### 🚀 Version initiale
- Application mobile Flutter fonctionnelle
- Backend Django avec API REST
- Authentification utilisateur
- Carte interactive avec Google Maps
- Gestion des escapes et des sessions
