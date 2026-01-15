# Guide de déploiement CityScape v0.2.1

## 📦 Contenu de cette version

### Backend Django
- Système de vérification de version (`/api/app-config`)
- Pages statiques pour Play Store
- Interface admin complète

### Application Mobile (Flutter)
- Version: 0.2.1 (versionCode 4)
- Système de mise à jour forcée
- Thèmes UI personnalisables
- Amélioration de la carte

### Interface Web (React)
- Application complète de gestion des escapes
- Dashboard créateur
- Éditeur d'étapes

---

## 🚀 Déploiement Backend

### Option 1: Script automatique (recommandé)

```bash
cd /chemin/vers/cityscape-monorepo
./deploy.sh
```

Le script effectue automatiquement:
1. Connexion SSH au serveur
2. Pull des modifications Git
3. Collecte des fichiers statiques
4. Redémarrage du service Django/Gunicorn
5. Nettoyage des anciens APK
6. Vérification des URLs

### Option 2: Déploiement manuel

```bash
# 1. Connexion au serveur
ssh deploy@api.cityscape.ovh

# 2. Navigation vers le projet
cd /var/www/cityscape

# 3. Pull des modifications
git fetch origin
git pull origin main

# 4. Activation de l'environnement virtuel
source venv/bin/activate

# 5. Installation des dépendances (si nécessaire)
pip install -r requirements.txt

# 6. Migrations de base de données (si nécessaire)
python manage.py migrate

# 7. Collecte des fichiers statiques
python manage.py collectstatic --noinput

# 8. Redémarrage du service
sudo systemctl restart gunicorn
sudo systemctl restart nginx

# 9. Vérification
systemctl status gunicorn
```

### Vérification post-déploiement Backend

Testez ces URLs:
- https://api.cityscape.ovh/ (page d'accueil Play Store)
- https://api.cityscape.ovh/downloads/ (redirection Play Store)
- https://api.cityscape.ovh/api/health (health check)
- https://api.cityscape.ovh/api/app-config (config version)
- https://api.cityscape.ovh/admin/ (interface admin)

---

## 📱 Déploiement Application Mobile

### 1. Vérifier les versions

```bash
cd mobile/cityscape_app
grep "version:" pubspec.yaml
# Doit afficher: version: 0.2.1+4

grep "versionCode\|versionName" android/app/build.gradle.kts
# Doit afficher: versionCode = 4, versionName = "0.2.1"
```

### 2. Build des fichiers

```bash
# APK pour test
flutter build apk --release

# AAB pour Play Store
flutter build appbundle --release
```

Fichiers générés:
- APK: `build/app/outputs/flutter-apk/app-release.apk` (58.4 MB)
- AAB: `build/app/outputs/bundle/release/app-release.aab` (48.0 MB)

### 3. Upload sur Google Play Console

1. Aller sur https://play.google.com/console
2. Sélectionner CityScape
3. Production > Créer une nouvelle version
4. Uploader `app-release.aab`
5. Ajouter les notes de version (voir CHANGELOG.md)
6. Soumettre pour révision

### 4. Programme bêta

Les testeurs peuvent rejoindre via:
https://play.google.com/apps/testing/com.roadpapattes.cityscape

---

## 🌐 Déploiement Interface React

### 1. Installation des dépendances

```bash
cd creator-web
npm install
```

### 2. Configuration

Créer le fichier `.env.production`:
```env
VITE_API_BASE_URL=https://api.cityscape.ovh
```

### 3. Build

```bash
npm run build
```

Fichiers générés dans `dist/`

### 4. Déploiement sur le serveur

**Option A: Via le serveur Django (même domaine)**

```bash
# Sur votre machine locale
cd creator-web
npm run build

# Copier vers le serveur
scp -r dist/* deploy@api.cityscape.ovh:/var/www/cityscape/creator-web-dist/

# Sur le serveur
ssh deploy@api.cityscape.ovh
cd /var/www/cityscape

# Configurer Nginx pour servir creator-web
# Ajouter dans la config Nginx:
# location /creator {
#     alias /var/www/cityscape/creator-web-dist;
#     try_files $uri $uri/ /index.html;
# }

sudo systemctl reload nginx
```

**Option B: Hébergement séparé (Netlify, Vercel, etc.)**

1. Connecter le dépôt GitHub
2. Configurer le build:
   - Build command: `npm run build`
   - Publish directory: `dist`
3. Variables d'environnement: `VITE_API_BASE_URL=https://api.cityscape.ovh`
4. Déployer

---

## ⚙️ Activation de la mise à jour forcée

### Quand forcer une mise à jour?

Forcez une mise à jour quand:
- Corrections de bugs critiques
- Changements d'API incompatibles
- Problèmes de sécurité
- Nouvelles fonctionnalités essentielles

### Comment activer

1. **Déployer la nouvelle version sur le Play Store d'abord**

2. **Modifier le backend** (`backend/urls.py`):

```python
def app_config(_):
    return JsonResponse({
        "min_version": "0.2.1",  # Version minimale requise
        "current_version": "0.2.1",  # Dernière version disponible
        "force_update": True,  # ⚠️ Activer ici
        "update_message": "Une mise à jour importante est disponible! Veuillez mettre à jour pour continuer."
    })
```

3. **Redémarrer le backend**:

```bash
ssh deploy@api.cityscape.ovh
sudo systemctl restart gunicorn
```

4. **Tester**:
   - Installer l'ancienne version sur un appareil de test
   - Ouvrir l'app
   - Vérifier que la dialog bloquante apparaît

### Désactiver la mise à jour forcée

Remettez `"force_update": False` après que la majorité des utilisateurs aient mis à jour.

---

## 🧪 Tests de vérification

### Backend
```bash
# Health check
curl https://api.cityscape.ovh/api/health
# Réponse attendue: {"status": "ok"}

# Version check
curl https://api.cityscape.ovh/api/app-config
# Réponse attendue: {"min_version": "0.2.0", ...}

# Page d'accueil
curl -I https://api.cityscape.ovh/
# Réponse attendue: HTTP 200
```

### Mobile
1. Installer l'APK sur un appareil de test
2. Vérifier le splash screen (vérification de version)
3. Tester les 3 thèmes UI
4. Vérifier la carte avec les nouveaux marqueurs
5. Tester les filtres sur la carte

### React
1. Se connecter avec un compte créateur
2. Créer un nouvel escape
3. Ajouter des étapes
4. Réordonner les étapes
5. Soumettre pour révision

---

## 🔧 Résolution de problèmes

### Le service ne redémarre pas

```bash
# Vérifier les logs
sudo journalctl -u gunicorn -n 50
sudo tail -f /var/www/cityscape/logs/gunicorn.log

# Vérifier le status
sudo systemctl status gunicorn
```

### Les fichiers statiques ne se chargent pas

```bash
python manage.py collectstatic --noinput
sudo systemctl restart nginx
```

### L'interface React ne se connecte pas à l'API

1. Vérifier `.env`: `VITE_API_BASE_URL=https://api.cityscape.ovh`
2. Vérifier CORS dans Django (`settings.py`)
3. Vérifier les logs réseau dans le navigateur (F12)

### La mise à jour forcée ne fonctionne pas

1. Vérifier que l'endpoint `/api/app-config` répond correctement
2. Vérifier la version dans `VersionCheckService.currentVersion`
3. Vérifier les logs du splash screen dans l'app

---

## 📊 Monitoring

### Métriques à surveiller

- Taux d'adoption de la nouvelle version
- Nombre d'utilisateurs bloqués par mise à jour forcée
- Temps de chargement de l'app
- Taux d'erreur de l'API

### Logs importants

```bash
# Backend
sudo tail -f /var/www/cityscape/logs/gunicorn.log
sudo journalctl -u gunicorn -f

# Nginx
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log
```

---

## 📞 Support

En cas de problème:
- Email: feedback.enigmapolis@gmail.com
- GitHub Issues: https://github.com/roadpapattes/cityscape/issues
