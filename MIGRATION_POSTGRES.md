# Runbook — Bascule SQLite → PostgreSQL

Procédure opérationnelle pour basculer la base de CityScape de SQLite vers
PostgreSQL sur le VPS. Le code est déjà prêt (config pilotée par variables
d'environnement) : la bascule et le rollback se font par une simple variable.

> Durée : ~30–45 min dont une courte fenêtre de maintenance (arrêt des
> écritures pendant le transfert). Réversible tant que `db.sqlite3` est intact.

Les commandes supposent le déploiement standard :
`APP_DIR=/srv/cityscape/app`, venv dans `/srv/cityscape/env`,
service systemd `cityscape-gunicorn`. Adapter si besoin.

---

## Résumé de la bascule

| Étape | Action | Réversible ? |
|-------|--------|--------------|
| 0 | Pré-requis (migrations à jour, backup SQLite) | — |
| 1 | Provisionner PostgreSQL (base + user UTF-8) | oui |
| 2 | Renseigner `.env` (base cible) | oui |
| 3 | **Répétition à blanc** (`REHEARSE=1`) | oui (aucun impact prod) |
| 4 | Bascule réelle (fenêtre de maintenance) | oui (rollback § dédié) |
| 5 | Contrôles fonctionnels | — |
| 6 | Post-migration (sauvegardes) | — |

---

## Étape 0 — Pré-requis

```bash
cd /srv/cityscape/app && source /srv/cityscape/env/bin/activate

# Dépendances à jour (psycopg, django-cors-headers)
pip install -r requirements.txt

# Historique des migrations cohérent → doit afficher "No changes detected"
python manage.py makemigrations --check --dry-run

# Backup de sécurité de la base actuelle
cp db.sqlite3 db.sqlite3.backup-$(date +%F)
```

---

## Étape 1 — Provisionner PostgreSQL

Postgres est généralement déjà installé. Sinon : `sudo apt install postgresql`.

```bash
sudo -u postgres psql <<'SQL'
CREATE USER cityscape WITH PASSWORD 'UN_MDP_FORT';
CREATE DATABASE cityscape OWNER cityscape
  ENCODING 'UTF8' LC_COLLATE 'fr_FR.UTF-8' LC_CTYPE 'fr_FR.UTF-8' TEMPLATE template0;
GRANT ALL PRIVILEGES ON DATABASE cityscape TO cityscape;
SQL
```

> Si la locale `fr_FR.UTF-8` n'existe pas : `sudo locale-gen fr_FR.UTF-8`
> d'abord, ou remplacer par `LC_COLLATE 'C' LC_CTYPE 'C'`.

---

## Étape 2 — Renseigner `.env` (DB_ENGINE encore commenté)

> ⚠️ Sur ce déploiement, **systemd lit le même `.env`** (`EnvironmentFile`).
> Tant que la bascule n'est pas faite, on laisse `DB_ENGINE` **commenté** :
> la prod reste sur SQLite même en cas de redémarrage.

À partir de `.env.example`, renseigner les paramètres PG mais garder
`DB_ENGINE` commenté (ne jamais committer `.env`) :

```
#DB_ENGINE=postgres
DB_NAME=cityscape
DB_USER=cityscape
DB_PASSWORD=UN_MDP_FORT
DB_HOST=127.0.0.1
DB_PORT=5432
```

Vérifier la connexion PG (override par le shell, sans activer `.env`) :

```bash
DB_ENGINE=postgres python manage.py dbshell   # doit ouvrir psql sur cityscape
```

---

## Étape 3 — Répétition à blanc (fortement recommandé)

Déroule toute la bascule **sans stopper le service ni activer `.env`** :
construit le schéma sur PG, importe les données, contrôle la parité, mais ne
touche pas à la prod (toujours sur SQLite). À faire au moins une fois.

```bash
DB_ENGINE=postgres REHEARSE=1 bash scripts/migrate_to_postgres.sh
```

Attendu en fin d'exécution : **`PARITÉ OK`**. En cas d'écart, le script
affiche le `diff` par modèle et s'arrête sans rien casser.

> Après la répétition, la base PG contient déjà les données. Avant la bascule
> réelle, on la remet à zéro pour repartir propre :
> ```bash
> sudo -u postgres psql -c "DROP DATABASE cityscape;"
> sudo -u postgres psql -c "CREATE DATABASE cityscape OWNER cityscape ENCODING 'UTF8' TEMPLATE template0;"
> ```

---

## Étape 4 — Bascule réelle

D'abord **activer** la bascule en décommentant la ligne dans `.env` (c'est ce
qui fera repartir gunicorn sur PG après le transfert) :

```
DB_ENGINE=postgres
```

Puis lancer le script. Fenêtre de maintenance : il stoppe les écritures,
transfère, contrôle la parité, puis redémarre. Si la parité échoue, il **ne
redémarre pas** sur PG.

```bash
bash scripts/migrate_to_postgres.sh
```

Ce que fait le script :
1. compte les lignes côté SQLite (source) ;
2. `sudo systemctl stop cityscape-gunicorn` (plus aucune écriture) ;
3. `dumpdata` (avec exclusions) → `migrate` sur PG → `loaddata` ;
4. `sqlsequencereset` (évite les collisions de PK à la prochaine insertion) ;
5. compte côté PG et **contrôle la parité** ;
6. `sudo systemctl start cityscape-gunicorn` si tout est OK.

---

## Étape 5 — Contrôles fonctionnels

```bash
curl -s https://api.cityscape.ovh/api/health         # {"status":"ok"}
```

- Admin `https://api.cityscape.ovh/admin/` → users présents, comptes identiques
- Dashboard creator `/creator/` → onglets Utilisateurs / Sessions / Surveys OK
- Soumettre un questionnaire test sur `/survey` → nouvelle ligne visible
- Vérifier un `nearby` (escapes autour d'un point) → résultats corrects

Comptage de contrôle :

```bash
python manage.py shell -c "from django.contrib.auth.models import User; print('users', User.objects.count())"
```

---

## Étape 6 — Post-migration

Sauvegardes automatiques (remplacent la copie de `db.sqlite3`). Cron quotidien :

```bash
pg_dump -U cityscape -h 127.0.0.1 cityscape | gzip > /srv/cityscape/backups/cityscape-$(date +\%F).sql.gz
```

Prévoir une rotation (7–14 jours) + un test de restauration.
Conserver `db.sqlite3.backup-*` plusieurs jours avant archivage.

---

## Rollback (si problème pendant/après la bascule)

1. `sudo systemctl stop cityscape-gunicorn`
2. Dans `.env` : commenter `DB_ENGINE=postgres` (retour SQLite)
3. `sudo systemctl start cityscape-gunicorn`

La base SQLite n'a pas été modifiée pendant le transfert (lecture seule) → état
intact. C'est pourquoi on stoppe les écritures à l'étape 4 : aucune donnée
créée pendant le transfert ne peut être perdue au rollback.

---

## Optionnel / plus tard — PostGIS (géospatial)

Une fois sur PostgreSQL, pour passer les requêtes `nearby` de Python (Haversine)
à des requêtes indexées en base. Chantier séparé, après une migration PG
stabilisée :

1. `CREATE EXTENSION postgis;` sur la base
2. `ENGINE: django.contrib.gis.db.backends.postgis` + `django.contrib.gis` dans `INSTALLED_APPS`
3. Passer `latitude/longitude` en `PointField` (migration + backfill)
4. Réécrire `nearby` avec `distance` / `dwithin` (GeoDjango)
