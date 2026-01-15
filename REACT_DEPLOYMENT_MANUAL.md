# Déploiement manuel de l'interface React

## Pré-requis: Installer Node.js sur le serveur

```bash
# 1. Se connecter au serveur
ssh deploy@api.cityscape.ovh

# 2. Installer Node.js (version LTS 20.x)
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

# 3. Vérifier l'installation
node --version  # Devrait afficher v20.x.x
npm --version   # Devrait afficher 10.x.x
```

## Déploiement de l'interface React

### Étape 1: Copier les fichiers sources sur le serveur

```bash
# Sur ta machine locale
cd /c/Users/lougi/cityscape-monorepo
scp -r creator-web deploy@api.cityscape.ovh:/tmp/
```

### Étape 2: Builder l'application sur le serveur

```bash
# Sur le serveur
ssh deploy@api.cityscape.ovh

# Aller dans le dossier temporaire
cd /tmp/creator-web

# Installer les dépendances
npm install

# Builder pour la production
npm run build

# Les fichiers buildés sont dans dist/
ls -lh dist/
```

### Étape 3: Déployer les fichiers statiques

```bash
# Créer le dossier de destination
sudo mkdir -p /var/www/cityscape/creator-web

# Copier les fichiers buildés
sudo cp -r dist/* /var/www/cityscape/creator-web/

# Définir les permissions
sudo chown -R www-data:www-data /var/www/cityscape/creator-web
sudo chmod -R 755 /var/www/cityscape/creator-web
```

### Étape 4: Configurer Nginx

```bash
# Éditer la configuration Nginx
sudo nano /etc/nginx/sites-available/cityscape

# Ajouter cette section dans le block server {}:
#
# location /creator {
#     alias /var/www/cityscape/creator-web;
#     try_files $uri $uri/ /creator/index.html;
#
#     # Headers pour les fichiers statiques
#     add_header Cache-Control "public, max-age=31536000, immutable";
# }
#
# # Fallback pour le routing React
# location /creator/ {
#     alias /var/www/cityscape/creator-web/;
#     try_files $uri $uri/ /creator/index.html;
# }

# Tester la configuration
sudo nginx -t

# Recharger Nginx
sudo systemctl reload nginx
```

### Étape 5: Vérification

Accéder à: https://api.cityscape.ovh/creator

Tu devrais voir l'interface React de création d'escapes.

## Troubleshooting

### Les fichiers CSS/JS ne se chargent pas

Vérifie que le chemin de base est correct dans `vite.config.js`:

```javascript
export default {
  base: '/creator/',
  // ...
}
```

Si ce n'est pas le cas, tu devras rebuild avec la bonne configuration.

### Erreur 404 sur les routes React

Assure-toi que la directive `try_files` dans Nginx redirige vers `index.html`.

### Problèmes de CORS

Vérifie que `VITE_API_BASE_URL` dans `.env.production` pointe bien vers `https://api.cityscape.ovh`.
