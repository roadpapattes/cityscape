#!/bin/bash
# Script de déploiement pour CityScape Backend

set -e  # Arrêt en cas d'erreur

# Configuration
SERVER_USER="deploy"
SERVER_HOST="api.cityscape.ovh"
REMOTE_PROJECT_DIR="/srv/cityscape/app"
REMOTE_ENV_DIR="/srv/cityscape/env"
DOWNLOADS_DIR="/var/www/cityscape/downloads"
GUNICORN_SERVICE="cityscape-gunicorn"

echo "🚀 Déploiement de CityScape Backend"
echo "=================================="

# 1. Vérifier la connexion SSH
echo "📡 Test de connexion SSH..."
ssh -o ConnectTimeout=10 "$SERVER_USER@$SERVER_HOST" "echo 'Connexion SSH réussie ✓'"

# 2. Pull des dernières modifications
echo ""
echo "📥 Récupération des dernières modifications..."
ssh "$SERVER_USER@$SERVER_HOST" << 'ENDSSH'
cd /srv/cityscape/app
echo "Branche actuelle :"
git branch --show-current
echo ""
echo "Pull des modifications..."
git fetch origin
git pull origin $(git branch --show-current)
echo "✓ Pull terminé"
ENDSSH

# 3. Appliquer les migrations de base de données
echo ""
echo "🗄️  Application des migrations..."
ssh "$SERVER_USER@$SERVER_HOST" << 'ENDSSH'
set -e
cd /srv/cityscape
source env/bin/activate 2>/dev/null || true
cd app
python manage.py migrate --noinput
echo "✓ Migrations appliquées"
ENDSSH

# 4. Collecter les fichiers statiques
echo ""
echo "📦 Collecte des fichiers statiques..."
ssh "$SERVER_USER@$SERVER_HOST" << 'ENDSSH'
cd /srv/cityscape
source env/bin/activate 2>/dev/null || true
cd app
python manage.py collectstatic --noinput || echo "⚠️ collectstatic échoué (peut-être pas nécessaire)"
echo "✓ Fichiers statiques collectés"
ENDSSH

# 5. Redémarrer le service Django
echo ""
echo "🔄 Redémarrage du service Django..."
ssh "$SERVER_USER@$SERVER_HOST" << 'ENDSSH'
# set -e : sans lui, un redémarrage réellement échoué affichait quand même
# "✓ Service redémarré" et le déploiement se poursuivait (même défaut que
# celui corrigé sur migrate).
set -e
echo "Redémarrage de cityscape-gunicorn..."
sudo systemctl restart cityscape-gunicorn
echo ""
echo "Status du service:"
# Pas de sudo ici : la règle sudoers ne couvre que `systemctl status
# cityscape-gunicorn` sans argument, donc l'ajout de `--no-pager -l` ne
# correspondait plus et réclamait un mot de passe — l'affichage échouait
# donc systématiquement. Ces deux requêtes ne demandent aucun privilège,
# et is-active renvoie un code non nul si le service n'a pas redémarré,
# ce qui fait maintenant échouer le déploiement.
systemctl is-active cityscape-gunicorn
systemctl show cityscape-gunicorn -p ActiveState -p SubState -p ActiveEnterTimestamp
echo "✓ Service redémarré"
ENDSSH

# 6. Nettoyer les anciens APK
echo ""
echo "🧹 Nettoyage des anciens APK..."
ssh "$SERVER_USER@$SERVER_HOST" << 'ENDSSH'
cd /var/www/cityscape/downloads
echo "Fichiers APK avant nettoyage :"
ls -lh *.apk 2>/dev/null || echo "Aucun APK trouvé"
echo ""
echo "Suppression des APK..."
rm -f *.apk *.apk.sha256 manifest.json 2>/dev/null || true
echo "✓ APK supprimés"
echo ""
echo "Fichiers restants dans downloads/ :"
ls -lh 2>/dev/null || echo "Répertoire vide"
ENDSSH

# 7. Vérification finale
echo ""
echo "✅ Vérification du déploiement..."
echo "Page d'accueil :"
curl -I https://api.cityscape.ovh/ | head -5
echo ""
echo "Page downloads :"
curl -I https://api.cityscape.ovh/downloads/ | head -5
echo ""

echo "=================================="
echo "✅ Déploiement terminé avec succès !"
echo ""
echo "URLs à vérifier :"
echo "  - https://api.cityscape.ovh/"
echo "  - https://api.cityscape.ovh/downloads/"
echo ""
