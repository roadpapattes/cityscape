# Installation du composant de carte interactive

Le composant `LocationPicker` nécessite les bibliothèques Leaflet pour fonctionner.

## Installation des dépendances

Exécutez la commande suivante dans le dossier `creator-web`:

```bash
npm install leaflet react-leaflet
```

## Fichiers modifiés

- **Nouveau**: `src/components/LocationPicker.jsx` - Composant de sélection de localisation avec carte
- **Modifié**: `src/pages/EscapeEditor.jsx` - Remplacement des champs latitude/longitude par LocationPicker

## Fonctionnalités

- **Carte interactive** avec OpenStreetMap
- **Clic sur la carte** pour placer un marqueur
- **Champs manuels** (optionnels) pour saisir les coordonnées exactes
- **Validation visuelle** avec affichage des coordonnées sélectionnées
- **Bouton effacer** pour réinitialiser la position

## Rebuild et déploiement

Après installation des dépendances:

```bash
# Build local
npm run build

# Sur le serveur (après copie des sources)
cd /tmp/creator-web
npm install
npm run build
sudo cp -r dist/* /var/www/cityscape/creator-web/
```

## Notes

- La carte utilise les tuiles OpenStreetMap (gratuites, pas besoin de clé API)
- Les marqueurs par défaut sont chargés depuis CDN (unpkg.com)
- Le centre par défaut est Paris (48.8566, 2.3522) si aucune position n'est définie
