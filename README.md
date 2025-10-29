
# Escape City API (Django simplifié)

API minimale pour démarrer ton MVP.

## Installation rapide

```bash
# 1) Créer un virtualenv (optionnel mais recommandé)
python -m venv .venv && source .venv/bin/activate  # macOS/Linux
# sous Windows: .venv\Scripts\activate

# 2) Installer les dépendances
pip install -r requirements.txt

# 3) Migrations + données de test
python manage.py makemigrations
python manage.py migrate
python manage.py loaddata games/fixtures_sample.json

# 4) Lancer le serveur
python manage.py runserver
```

API disponible sur: http://127.0.0.1:8000/api/

### Endpoints
- `GET /api/escapes/` — liste des escape games
- `POST /api/escapes/` — créer un escape game
- `GET /api/escapes/{id}/` — détail
- `PUT/PATCH /api/escapes/{id}/` — modifier
- `DELETE /api/escapes/{id}/` — supprimer
- `GET /api/escapes/nearby?lat=48.8566&lon=2.3522&radius_km=5` — autour d'un point (trié par distance)

### Notes
- Base SQLite par défaut (`db.sqlite3`).
- Calcul de distance via **Haversine** (côté Python). Pour la prod, on migrera vers **PostGIS** pour les requêtes géospatiales.
