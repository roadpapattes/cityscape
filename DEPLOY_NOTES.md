# Notes de Deploiement - Cityscape

## Connexion au serveur

```bash
ssh deploy@api.cityscape.ovh
```

## Chemins importants

| Description | Chemin |
|------------|--------|
| Code source (git) | `/srv/cityscape/app` |
| Creator-web build (nginx) | `/var/www/cityscape/creator-web` |
| Environnement virtuel Python | `/srv/cityscape/env` |

## Deploiement Backend (Django/Gunicorn)

```bash
cd /srv/cityscape/app
git pull
sudo systemctl restart cityscape-gunicorn
```

## Deploiement Creator-Web (React/Vite)

```bash
cd /srv/cityscape/app
git pull
cd creator-web
npm install --legacy-peer-deps
npm run build
sudo cp -r dist/* /var/www/cityscape/creator-web/
```

## Services systemd

| Service | Commande restart |
|---------|-----------------|
| Gunicorn (API Django) | `sudo systemctl restart cityscape-gunicorn` |
| Nginx (fichiers statiques) | `sudo systemctl restart nginx` |

## Verifier les logs

```bash
# Logs Gunicorn
sudo journalctl -u cityscape-gunicorn -f

# Logs Nginx
sudo tail -f /var/log/nginx/error.log
```

## Configuration app mobile (force update)

Le fichier `backend/urls.py` contient la configuration de version pour forcer les mises a jour:

```python
def app_config(_):
    return JsonResponse({
        "min_version": "X.Y.Z",
        "current_version": "X.Y.Z",
        "force_update": True,
        "update_message": "..."
    })
```

Apres modification, deployer le backend et restart gunicorn.
