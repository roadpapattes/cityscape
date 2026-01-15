#!/bin/bash
# Script de déploiement pour CityScape Backend

set -e  # Arrêt en cas d'erreur

# Configuration
SERVER_USER="deploy"
SERVER_HOST="api.cityscape.ovh"
REMOTE_PROJECT_DIR="/var/www/cityscape"
DOWNLOADS_DIR="/var/www/cityscape/downloads"
BRANCH="claude/redirect-apk-playstore-uKVtR"

echo "🚀 Déploiement de CityScape Backend"
echo "=================================="

# 1. Vérifier la connexion SSH
echo "📡 Test de connexion SSH..."
ssh -o ConnectTimeout=10 "$SERVER_USER@$SERVER_HOST" "echo 'Connexion SSH réussie ✓'"

# 2. Pull des dernières modifications
echo ""
echo "📥 Récupération des dernières modifications..."
ssh "$SERVER_USER@$SERVER_HOST" << 'ENDSSH'
cd /var/www/cityscape
echo "Branche actuelle :"
git branch --show-current
echo ""
echo "Pull des modifications..."
git fetch origin
git pull origin $(git branch --show-current)
echo "✓ Pull terminé"
ENDSSH

# 3. Collecter les fichiers statiques
echo ""
echo "📦 Collecte des fichiers statiques..."
ssh "$SERVER_USER@$SERVER_HOST" << 'ENDSSH'
cd /var/www/cityscape
source venv/bin/activate 2>/dev/null || true
python manage.py collectstatic --noinput || echo "⚠️ collectstatic échoué (peut-être pas nécessaire)"
echo "✓ Fichiers statiques collectés"
ENDSSH

# 4. Redémarrer le service Django
echo ""
echo "🔄 Redémarrage du service Django..."
ssh "$SERVER_USER@$SERVER_HOST" << 'ENDSSH'
# Essayer systemd d'abord
if systemctl list-unit-files | grep -q "cityscape\|django\|gunicorn"; then
    SERVICE_NAME=$(systemctl list-unit-files | grep -E "cityscape|django|gunicorn" | head -1 | awk '{print $1}')
    echo "Service trouvé : $SERVICE_NAME"
    sudo systemctl restart $SERVICE_NAME
    sudo systemctl status $SERVICE_NAME --no-pager -l
elif [ -f /etc/init.d/cityscape ]; then
    sudo /etc/init.d/cityscape restart
else
    echo "⚠️ Service non trouvé. Essayez de redémarrer manuellement."
    echo "Commandes possibles :"
    echo "  - systemctl restart gunicorn"
    echo "  - systemctl restart nginx"
    echo "  - pkill -HUP gunicorn"
fi
echo "✓ Service redémarré"
ENDSSH

# 5. Nettoyer les anciens APK
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

# 6. Vérification finale
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
