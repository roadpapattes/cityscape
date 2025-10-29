
# Escape City Client - Google Maps + Autour de moi (complet)

## Démarrage
```bash
flutter create .
flutter pub get
```
- Ajoute ta **clé Google Maps** dans `android/app/src/main/AndroidManifest.xml` (com.google.android.geo.API_KEY)
- Vérifie `baseUrl` dans `lib/main.dart` (émulateur Android = http://10.0.2.2:8000)
- Lance Django côté PC (`python manage.py runserver`)
- Puis lance Flutter : `flutter run`

## Fonctionnalités
- Onglet **Liste** (recherche proximité) et **Carte**
- Bouton **Autour de moi** (GPS) : permissions, centrage carte, requête `/nearby`
- Permissions Android déjà ajoutées
