# 🚀 Notes de version CityScape v0.2.1

**Date de sortie**: 15 janvier 2026
**Version mobile**: 0.2.1 (versionCode 4)
**Fichiers prêts**: ✅ APK (58.4MB) & AAB (48.0MB)

---

## 📝 Résumé exécutif

Cette version majeure combine:
1. **Système de mise à jour forcée** pour garantir que tous les utilisateurs utilisent la dernière version
2. **Interface Play Store** avec programme bêta
3. **Application React** complète pour la gestion des escapes
4. **Améliorations UI mobile** avec thèmes personnalisables et carte améliorée

---

## 🎯 Nouveautés principales

### 1. Système de mise à jour forcée 🔄

**Pourquoi?** Permet de forcer les utilisateurs à mettre à jour l'app en cas de bug critique ou changement d'API.

**Comment ça marche?**
- Au démarrage, l'app vérifie `/api/app-config`
- Si `force_update: true` et version < `min_version`, une dialog bloquante s'affiche
- L'utilisateur doit mettre à jour depuis le Play Store pour continuer

**Activation:**
```python
# backend/urls.py
def app_config(_):
    return JsonResponse({
        "min_version": "0.2.1",
        "force_update": True,  # ← Activer ici
        "update_message": "Mise à jour requise!"
    })
```

### 2. Interface Play Store 🏪

**Pages créées:**
- `/` - Page d'accueil avec bouton Play Store + bouton programme bêta
- `/downloads/` - Redirection pour anciens liens APK

**Programme bêta:**
- URL directe: https://play.google.com/apps/testing/com.roadpapattes.cityscape
- Les testeurs reçoivent automatiquement les versions bêta

### 3. Application React (Creator Interface) 💻

**Interface web complète** accessible depuis un navigateur pour:
- Créer et éditer des escapes
- Gérer les étapes (5 types d'énigmes)
- Réordonner les étapes (drag & drop)
- Soumettre pour révision

**URL de production:** https://api.cityscape.ovh/creator/

**Technos:**
- React + Vite
- API REST avec authentification par token
- Interface moderne et responsive

### 4. Améliorations mobile 📱

**Thèmes UI:**
- 3 styles visuels: Card Collection (par défaut), Gaming UI, Playful
- Sélection dans le profil utilisateur
- AppBar et BottomNav thématisés

**Carte améliorée:**
- Marqueurs personnalisés avec gradients
- Bottom sheet animé pour détails
- Filtres (difficulté, note, favoris)
- Cercle de rayon de recherche
- Mode sombre

---

## 📦 Fichiers livrables

### Backend
- ✅ Code source avec merge complet
- ✅ Script de déploiement (`deploy.sh`)
- ✅ Pages statiques HTML
- ✅ Documentation complète

### Mobile
- ✅ APK: `build/app/outputs/flutter-apk/app-release.apk` (58.4MB)
- ✅ AAB: `build/app/outputs/bundle/release/app-release.aab` (48.0MB)
- ✅ Version: 0.2.1 (versionCode 4)

### React
- ✅ Code source complet dans `creator-web/`
- ✅ README avec instructions
- ✅ Configuration Vite
- ✅ Déployé sur https://api.cityscape.ovh/creator/

---

## 🚀 Plan de déploiement recommandé

### Étape 1: Backend (30 minutes)
```bash
cd /chemin/vers/cityscape-monorepo
./deploy.sh
```

**Vérifier:**
- https://api.cityscape.ovh/
- https://api.cityscape.ovh/api/app-config
- https://api.cityscape.ovh/downloads/
- https://api.cityscape.ovh/creator/

### Étape 2: Mobile (2-3 jours pour validation Google)
1. Upload `app-release.aab` sur Google Play Console
2. Ajouter notes de version (copier depuis CHANGELOG.md)
3. Soumettre pour révision
4. Attendre validation Google (24-72h généralement)
5. Publier en production

### Étape 3: React ✅ DÉPLOYÉ
L'interface React est déjà déployée et accessible sur:
**https://api.cityscape.ovh/creator/**

Pour redéployer après modifications:
```bash
# Sur le serveur
ssh deploy@api.cityscape.ovh
cd /tmp/creator-web
npm run build
sudo cp -r dist/* /var/www/cityscape/creator-web/
```

### Étape 4: Activer mise à jour forcée (5 minutes)
**UNIQUEMENT après que l'app soit disponible sur le Play Store!**

1. Modifier `backend/urls.py`: `"force_update": True`
2. Redémarrer: `sudo systemctl restart gunicorn`

---

## ⚠️ Points d'attention

### 1. Ne PAS activer force_update avant publication Play Store
Si vous activez `force_update: true` avant que la v0.2.1 soit disponible sur le Play Store, les utilisateurs seront bloqués!

### 2. Tester le programme bêta
Avant d'activer force_update en production, testez avec quelques utilisateurs du programme bêta.

### 3. Sauvegarder la base de données
Avant tout déploiement backend:
```bash
ssh deploy@api.cityscape.ovh
cd /var/www/cityscape
python manage.py dumpdata > backup_$(date +%Y%m%d_%H%M%S).json
```

### 4. Vérifier les versions
```bash
# Sur votre machine
cd mobile/cityscape_app
grep "version:" pubspec.yaml
# Doit afficher: 0.2.1+4
```

---

## 📊 Métriques à surveiller

### Jour 1-3 (Après publication Play Store)
- Nombre de téléchargements v0.2.1
- Taux d'adoption (%) des nouveaux utilisateurs
- Crashs ou bugs critiques

### Jour 3-7 (Après activation force_update)
- Nombre d'utilisateurs bloqués par la dialog
- Taux de mise à jour (combien passent de 0.2.0 à 0.2.1)
- Feedback des utilisateurs

### Hebdomadaire
- Utilisation de l'interface React (nouveaux escapes créés)
- Inscriptions au programme bêta
- Temps de chargement de l'app

---

## 🐛 Que faire en cas de problème?

### Si l'app ne passe pas la validation Google Play
- Vérifier les logs de validation
- Problème fréquent: Permissions manquantes dans AndroidManifest.xml
- Corriger et re-soumettre (pas besoin de changer versionCode si pas encore publié)

### Si les utilisateurs sont bloqués par force_update
**Action immédiate:**
```bash
# Désactiver temporairement
ssh deploy@api.cityscape.ovh
# Éditer backend/urls.py: "force_update": False
sudo systemctl restart gunicorn
```

### Si le backend ne démarre pas après déploiement
```bash
# Vérifier les logs
ssh deploy@api.cityscape.ovh
sudo journalctl -u gunicorn -n 50
sudo tail -f /var/www/cityscape/logs/gunicorn.log

# Rollback si nécessaire
git reset --hard HEAD~1
sudo systemctl restart gunicorn
```

---

## 📞 Support et contacts

### Pour les utilisateurs
- Email: feedback.enigmapolis@gmail.com
- Programme bêta: https://play.google.com/apps/testing/com.roadpapattes.cityscape

### Documentation
- `CHANGELOG.md` - Historique détaillé des versions
- `DEPLOYMENT.md` - Guide de déploiement complet
- `creator-web/README.md` - Documentation React

---

## ✅ Checklist finale avant déploiement

### Backend
- [ ] Backup de la base de données effectué
- [ ] Tests locaux OK
- [ ] Script `deploy.sh` testé
- [ ] URLs vérifiées après déploiement
- [ ] `force_update` = `False` (au début!)

### Mobile
- [ ] Version correcte dans tous les fichiers
- [ ] APK testé sur appareil physique
- [ ] AAB généré et vérifié
- [ ] Notes de version rédigées
- [ ] Upload sur Google Play Console

### React
- [x] `npm run build` réussi
- [x] `.env.production` configuré
- [x] Déployé sur https://api.cityscape.ovh/creator/
- [x] Assets JS/CSS chargent correctement
- [x] Nginx configuré avec routing React

### Post-déploiement
- [ ] App v0.2.1 disponible sur Play Store
- [ ] Quelques utilisateurs testent en bêta
- [ ] Pas de bugs critiques remontés (attendre 24-48h)
- [ ] Activer `force_update` si nécessaire

---

## 🎉 Conclusion

Cette version 0.2.1 est une étape majeure pour CityScape:
- **Contrôle des versions** avec système de mise à jour forcée
- **Distribution officielle** via Google Play Store
- **Outil de gestion** professionnel avec l'interface React
- **UX améliorée** avec thèmes personnalisables et carte enrichie

Tous les fichiers sont prêts pour le déploiement. Bon courage! 🚀

---

**Dernière mise à jour**: 15 janvier 2026
**Préparé par**: Claude Sonnet 4.5
**Contact**: feedback.enigmapolis@gmail.com
