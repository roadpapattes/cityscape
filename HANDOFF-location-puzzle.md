# Passation — Énigme « Point à atteindre » (validation par position GPS)

> Note destinée à la prochaine session Claude Code, reprise dans VS Code.
> Contexte : nouveau type d'étape `location` où le joueur valide en se
> déplaçant physiquement sur un point (pas de réponse à saisir). Le travail
> est terminé et poussé ; il reste à merger, déployer et tester sur le terrain.

## État actuel

- **Branche** : `claude/player-movement-puzzle-validation-q77uty`
- **PR ouverte** : #28 → base `main` (https://github.com/roadpapattes/cityscape/pull/28)
- **Validé automatiquement** : `manage.py check` (0 issue) et
  `makemigrations games --check --dry-run` (aucune dérive → migration `0024`
  fidèle au modèle).
- **PAS encore fait** : `flutter analyze` (SDK Flutter absent de l'env web) et
  le test terrain avec GPS réel.

## Ce que fait la fonctionnalité (rappel)

Type `GameStep.answer_type = "location"`. La cible = `latitude`/`longitude` de
l'étape, tolérance = `radius_m`. 3 modes d'aide (`reveal_mode`) :
- `guided` : point affiché sur la carte + jauge + distance.
- `hotcold` : jauge chaud/froid 5 nuances (bleu → rouge foncé), cible masquée.
- `blind` : aucune aide.
`auto_validate` = validation auto à l'entrée du rayon (ON par défaut) ; si OFF,
bouton « Valider ma position ». La validation est **arbitrée côté serveur**
(distance haversine + endpoint `/sessions/proximity` qui ne divulgue jamais la
cible en hotcold/blind).

## Prochaines étapes (dans l'ordre)

### 1. Merger la PR #28 dans `main`
Relire le diff si besoin, puis merge. Rien d'autre à coder pour la v1.

### 2. Récupérer `main` en local
```bash
git checkout main
git pull
```

### 3. Vérifier le mobile (SEULE partie non validée)
```bash
cd mobile/cityscape_app
flutter pub get
flutter analyze     # corriger ce qui remonte (probables lints : withOpacity déprécié, etc.)
```
Zones touchées à re-regarder si `analyze` râle :
- `lib/main.dart` : `_startLocationTracking` / `_pingProximity` /
  `_submitLocation` / `_buildLocationPuzzle` + branche de parsing `location`.
- `lib/models/game_step.dart` : champs `radiusM` / `revealMode` / `autoValidate`.
- `lib/services/api/api_service.dart` : `submitAnswer(latitude/longitude)` +
  `proximityPing`.

### 4. Bumper la version mobile (4 fichiers — actuel : `0.3.24+38`)
Cible : `0.3.25+39`.
| Fichier | Champ | Valeur |
|---|---|---|
| `mobile/cityscape_app/android/app/build.gradle.kts` | `versionCode` | `39` |
| `mobile/cityscape_app/android/app/build.gradle.kts` | `versionName` | `"0.3.25"` |
| `mobile/cityscape_app/pubspec.yaml` | `version` | `0.3.25+39` |
| `mobile/cityscape_app/lib/services/version_check_service.dart` | `currentVersion` | `'0.3.25'` |

### 5. Déployer le backend — AVEC migration
`deploy.sh` applique désormais `migrate` automatiquement. En manuel :
```bash
ssh deploy@api.cityscape.ovh
cd /srv/cityscape/app && git pull
source /srv/cityscape/env/bin/activate
python manage.py migrate --noinput
python manage.py collectstatic --noinput
sudo systemctl restart cityscape-gunicorn
```
Vérif : `python manage.py showmigrations games | tail -3` → `[X] 0024_gamestep_location_puzzle`.

### 6. Déployer le créateur web (sinon l'option n'apparaît pas dans l'éditeur)
```bash
cd creator-web && npm install && npm run build
scp -r dist/* deploy@api.cityscape.ovh:/var/www/cityscape/creator-web/
```
(`.env.production` : `VITE_API_BASE_URL=https://api.cityscape.ovh`)

### 7. Compiler l'AAB (tape la prod par défaut, pas de dart-define nécessaire)
```bash
cd mobile/cityscape_app
flutter build appbundle --release
# -> build/app/outputs/bundle/release/app-release.aab
```

### 8. Play Console (canal test interne) + test terrain
Créer une étape « Point à atteindre » via le créateur, publier l'escape, puis
tester en se déplaçant. Cas à couvrir :
- les 3 modes (`guided` / `hotcold` / `blind`) ;
- `auto_validate` ON et OFF (bouton manuel) ;
- anti-triche : en hotcold/blind, la réponse `/sessions/state` ne doit PAS
  contenir la lat/lon de la cible ;
- indice de secours (le filet) ;
- refus de localisation → message d'erreur + bouton « Réessayer ».

## Ordre impératif
**Backend (+migrate) et créateur-web AVANT l'AAB.** Sinon `/proximity` et la
validation position renverront des 500.

## Points ouverts / décisions à confirmer
- Un « trop loin » n'applique **pas** de pénalité de temps (volontaire). À
  rediscuter si on veut pénaliser les validations manuelles ratées.
- Throttle du ping proximité : ~3 s (`_lastPingMs` dans `main.dart`). Ajuster
  selon conso batterie/réseau observée sur le terrain.
- iOS : vérifier `NSLocationWhenInUseUsageDescription` dans
  `ios/Runner/Info.plist` si build iPhone.

## Idées de suite (backlog, hors v1)
Modes plus riches déjà esquissés en conception : points de passage ordonnés,
tracé/dessin GPS, position relative (« place-toi pour que X soit entre toi et
Y »). La brique « distance à une cible avec tolérance » de la v1 les alimente.
