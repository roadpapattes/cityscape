# CityScape Creator Interface

Interface web pour la création et la gestion d'escapes urbains.

## 🚀 Démarrage rapide

```bash
npm install
npm run dev
```

L'application sera accessible sur `http://localhost:5173`

## 📋 Fonctionnalités

- ✅ Authentification
- ✅ Dashboard créateur
- ✅ Création/édition d'escapes
- ✅ Gestion des étapes (5 types d'énigmes)
- ✅ Système d'indices
- ✅ Géolocalisation
- ✅ Soumission pour révision

## 🏗️ Structure

```
src/
├── api/client.js       # API client
├── components/         # Composants réutilisables
├── pages/             # Pages principales
├── styles/            # CSS global
└── App.jsx            # Routing
```

## 🔧 Configuration

Fichier `.env` :
```
VITE_API_BASE_URL=https://api.cityscape.ovh
```
