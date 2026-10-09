# Déploiement de l'interface créateur (React)

L'interface créateur web est une application Vite/React servie en fichiers
statiques par nginx, sous `https://api.cityscape.ovh/creator`.

Le serveur possède déjà le dépôt dans `/srv/cityscape/app`, et `deploy.sh` l'y
met à jour à chaque déploiement backend. **On construit donc directement sur le
serveur**, à partir du code déjà présent : il n'y a rien à copier depuis la
machine de développement.

## Déploiement

### 1. Mettre le code à jour sur le serveur

Soit par `bash deploy.sh` depuis la machine de développement (qui fait le
`git pull`), soit à la main :

```bash
ssh deploy@api.cityscape.ovh
cd /srv/cityscape/app && git pull origin main
```

### 2. Construire

```bash
cd /srv/cityscape/app/creator-web
npm install   # seulement si package.json a changé
npm run build
```

Le résultat est dans `dist/`. Le nom des fichiers JS et CSS contient une
empreinte du contenu (`index-DgiE08jk.js`), qui change à chaque modification :
c'est ce qui permet le cache long côté navigateur.

Aucun privilège n'est requis pour ces deux étapes : `dist/` appartient à
`deploy`.

### 3. Publier

```bash
sudo rsync -a --delete /srv/cityscape/app/creator-web/dist/ /var/www/cityscape/creator-web/
sudo chown -R www-data:www-data /var/www/cityscape/creator-web
sudo chmod -R 755 /var/www/cityscape/creator-web
```

**Ne pas utiliser `cp -r dist/*`.** C'était la procédure précédente, et comme
`cp` ajoute sans jamais retirer, chaque déploiement laissait derrière lui le
bundle de la fois d'avant. En octobre 2026 le répertoire contenait quatorze
bundles obsolètes, soit 6 Mo de fichiers que plus rien ne référençait.

`rsync -a --delete` fait du répertoire publié le miroir exact du build : le
nouveau bundle arrive, les anciens partent, et le problème ne revient pas.
Attention toutefois : `--delete` supprime tout ce qui n'est pas dans `dist/`.
Ne jamais déposer de fichier à la main dans `/var/www/cityscape/creator-web/`,
il serait effacé au déploiement suivant.

### 4. Vérifier

```bash
curl -s https://api.cityscape.ovh/creator/ | grep -oE 'assets/[A-Za-z0-9._-]+'
```

Les noms affichés doivent être ceux que `npm run build` vient de produire. Si
c'est encore l'ancien bundle, la copie n'a pas abouti.

## Configuration nginx

Déjà en place dans `/etc/nginx/sites-available/cityscape`, reproduite ici pour
mémoire :

```nginx
location /creator {
  alias /var/www/cityscape/creator-web;
  try_files $uri $uri/ /creator/index.html;
  index index.html;

  # Fichiers hashés (nom change à chaque build) : cache long sans risque
  location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)$ {
    expires 1y;
    add_header Cache-Control "public, immutable";
  }

  # index.html : jamais de cache navigateur, sinon les déploiements
  # suivants restent invisibles tant que le cache n'expire pas
  location = /creator/index.html {
    add_header Cache-Control "no-cache, must-revalidate";
  }
}
```

La distinction entre les deux blocs est essentielle et ne doit pas être
simplifiée. `index.html` porte le nom du bundle courant : s'il était mis en
cache comme les autres fichiers, un navigateur continuerait de demander
l'ancien JS pendant un an. Inversement, les fichiers hashés peuvent être mis en
cache sans limite, puisqu'un changement de contenu change leur nom.

Rappel sur `add_header` dans nginx : il n'est **pas** cumulatif. Dès qu'un bloc
`location` en déclare un, il perd tous ceux hérités du bloc parent. Ajouter un
en-tête dans l'un de ces deux sous-blocs oblige donc à y recopier les autres.

Après toute modification :

```bash
sudo nginx -t && sudo systemctl reload nginx
```

## En cas de problème

### Les fichiers CSS/JS ne se chargent pas

Le chemin de base doit correspondre à l'emplacement servi. Dans
`creator-web/vite.config.js` :

```javascript
export default {
  base: '/creator/',
}
```

### Erreur 404 sur une route interne de l'application

C'est le `try_files ... /creator/index.html` qui renvoie le routage à React. Le
vérifier dans la configuration nginx.

### L'ancien contenu s'affiche encore

Comparer le bundle référencé par la page servie avec celui du dernier build
(étape 4). Si les noms diffèrent, la copie a échoué. S'ils sont identiques et
que l'affichage reste ancien, vider le cache du navigateur — mais c'est
inattendu, `index.html` étant servi en `no-cache`.

### Problèmes de CORS

`VITE_API_BASE_URL` dans `.env.production` doit pointer vers
`https://api.cityscape.ovh`. Côté serveur, `CORS_ALLOWED_ORIGINS` est lu depuis
le `.env` (voir `backend/settings.py`).
