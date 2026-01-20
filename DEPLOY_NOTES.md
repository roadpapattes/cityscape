# Notes de Deploiement - Cityscape

## Connexion au serveur

```bash
ssh deploy@api.cityscape.ovh
```

## Chemins importants

### Serveur (OVH VPS)

| Description | Chemin |
|-------------|--------|
| Code source (git) | `/srv/cityscape/app` |
| Creator-web build (nginx) | `/var/www/cityscape/creator-web` |
| Environnement virtuel Python | `/srv/cityscape/env` |

### Local (Windows)

| Description | Chemin |
|-------------|--------|
| Monorepo | `c:\Users\lougi\cityscape-monorepo` |
| App Flutter | `c:\Users\lougi\cityscape-monorepo\mobile\cityscape_app` |
| AAB genere | `mobile\cityscape_app\build\app\outputs\bundle\release\app-release.aab` |

---

## CHECKLIST - Nouvelle version mobile (AAB)

**AVANT de compiler, verifier que TOUS ces fichiers sont a jour :**

### 1. Fichiers de version (3 fichiers a modifier)

| Fichier | Champ | Exemple |
|---------|-------|---------|
| `mobile/cityscape_app/android/app/build.gradle.kts` | `versionCode` | `9` |
| `mobile/cityscape_app/android/app/build.gradle.kts` | `versionName` | `"0.2.5"` |
| `mobile/cityscape_app/pubspec.yaml` | `version` | `0.2.5+9` |
| `mobile/cityscape_app/lib/services/version_check_service.dart` | `currentVersion` | `'0.2.5'` |

**IMPORTANT** : Le `currentVersion` dans `version_check_service.dart` est souvent oublie !

### 2. Backend (force update)

| Fichier | Champ |
|---------|-------|
| `backend/urls.py` | `min_version`, `current_version`, `force_update` |

### 3. Compilation

```bash
cd c:\Users\lougi\cityscape-monorepo\mobile\cityscape_app
flutter build appbundle --release
```

### 4. Apres publication Google Play

Deployer le backend pour activer le force update :
```bash
# Sur le serveur
cd /srv/cityscape/app
git pull
sudo systemctl restart cityscape-gunicorn
```

---

## Deploiement Backend (Django/Gunicorn)

```bash
cd /srv/cityscape/app
git pull
sudo systemctl restart cityscape-gunicorn
```

**Note** : Le service s'appelle `cityscape-gunicorn` (pas juste `gunicorn`)

---

## Deploiement Creator-Web (React/Vite)

### Sur le serveur

```bash
cd /srv/cityscape/app
git pull
cd creator-web
npm install --legacy-peer-deps
npm run build
sudo cp -r dist/* /var/www/cityscape/creator-web/
```

### En local (si npm fonctionne)

```bash
cd c:\Users\lougi\cityscape-monorepo\creator-web
npm install --legacy-peer-deps
npm run build
```

Puis copier via scp ou deployer via git sur le serveur.

---

## Services systemd

| Service | Commande restart |
|---------|------------------|
| Gunicorn (API Django) | `sudo systemctl restart cityscape-gunicorn` |
| Nginx (fichiers statiques) | `sudo systemctl restart nginx` |

---

## Verifier les logs

```bash
# Logs Gunicorn
sudo journalctl -u cityscape-gunicorn -f

# Logs Nginx
sudo tail -f /var/log/nginx/error.log
```

---

## Verifier la config app-config

```bash
curl -s https://api.cityscape.ovh/api/app-config
```

Doit retourner :
```json
{
  "min_version": "X.Y.Z",
  "current_version": "X.Y.Z",
  "force_update": true/false,
  "update_message": "..."
}
```

---

## Erreurs courantes

### "git pull" echoue avec des changements locaux
```bash
git stash
git pull
```

### npm ERESOLVE dependency conflict
```bash
npm install --legacy-peer-deps
```

### Permission denied sur le serveur
Utiliser `sudo` pour les operations dans `/var/www/`

---

## Historique des versions

| Version | versionCode | Date | Notes |
|---------|-------------|------|-------|
| 0.2.7 | 11 | 2026-01-20 | Fix session creation on detail view, image upload web |
| 0.2.6 | 10 | 2026-01-20 | Profile display name fix for Google users |
| 0.2.5 | 9 | 2025-01-17 | Fix version_check_service.dart, show_location toggle |
| 0.2.4 | 8 | 2025-01-17 | show_location feature |
| 0.2.3 | 7 | 2025-01-16 | Bug fixes, force update |
