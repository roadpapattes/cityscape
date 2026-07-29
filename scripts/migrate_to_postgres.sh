#!/usr/bin/env bash
#
# Bascule des données SQLite -> PostgreSQL pour CityScape.
#
# Enchaîne dumpdata (depuis SQLite) -> migrate (schéma PG) -> loaddata ->
# sqlsequencereset, avec des garde-fous : arrêt des écritures, contrôle de
# connexion, et VÉRIFICATION DE PARITÉ DES COMPTES par modèle avant/après.
#
# Réversible : la base SQLite est lue seule, jamais modifiée. En cas de
# problème, on recommente DB_ENGINE=postgres dans .env et on redémarre.
#
# Pré-requis :
#   - .env renseigné avec DB_ENGINE=postgres + DB_* (base PG déjà créée en UTF-8)
#   - le service applicatif est arrêté (ce script le fait si SERVICE est défini)
#
# Usage :
#   bash scripts/migrate_to_postgres.sh
#   REHEARSE=1 bash scripts/migrate_to_postgres.sh   # répétition à blanc (ne stoppe pas le service)
#
set -euo pipefail

# --- Configuration (surchargeable par variables d'environnement) -------------
APP_DIR="${APP_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PY="${PY:-python}"                         # ex: /srv/cityscape/env/bin/python
DUMP_FILE="${DUMP_FILE:-$APP_DIR/dump.json}"
SERVICE="${SERVICE:-cityscape-gunicorn}"   # service systemd à stopper (vide = ne rien stopper)
SEQ_APPS="${SEQ_APPS:-engagement games surveys authtoken auth}"
REHEARSE="${REHEARSE:-0}"                   # 1 = répétition à blanc : ne stoppe pas le service

cd "$APP_DIR"

log()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
die()  { printf '\n\033[1;31mERREUR: %s\033[0m\n' "$*" >&2; exit 1; }

# Compte les lignes par modèle, en excluant les modèles NON transférés
# (contenttypes/permissions recréés par migrate ; sessions/logentry exclus du dump).
# Sortie : "app_label.model<TAB>count", triée. Sert de base de comparaison.
count_rows() {
  "$PY" manage.py shell -c '
from django.apps import apps
EXCLUDE = {"contenttypes.contenttype", "auth.permission",
           "admin.logentry", "sessions.session"}
rows = []
for m in apps.get_models():
    label = m._meta.label_lower
    if label in EXCLUDE:
        continue
    try:
        rows.append((label, m.objects.count()))
    except Exception:
        pass
for label, n in sorted(rows):
    print(f"{label}\t{n}")
'
}

# --- 0. Pré-vol -------------------------------------------------------------
[ -f manage.py ] || die "manage.py introuvable dans $APP_DIR"
grep -q '^DB_ENGINE=postgres' .env 2>/dev/null \
  || die ".env doit contenir DB_ENGINE=postgres (base PG cible déjà créée)."

log "Vérification de la connexion PostgreSQL"
DB_ENGINE=postgres "$PY" manage.py check --database default \
  || die "Connexion PG KO. Vérifier .env (DB_*) et que la base existe."

# --- 1. Comptage SOURCE (SQLite) -------------------------------------------
log "Comptage des lignes côté SQLite (source)"
SRC_COUNTS="$(DB_ENGINE= count_rows)" || die "Comptage SQLite échoué."
echo "$SRC_COUNTS"

# --- 2. Fenêtre de maintenance : stopper les écritures ----------------------
if [ "$REHEARSE" = "0" ] && [ -n "$SERVICE" ]; then
  log "Arrêt du service $SERVICE (fenêtre de maintenance)"
  sudo systemctl stop "$SERVICE" || die "Impossible de stopper $SERVICE."
else
  log "Répétition à blanc : le service n'est PAS stoppé."
fi

# --- 3. Export depuis SQLite ------------------------------------------------
log "dumpdata depuis SQLite -> $DUMP_FILE"
DB_ENGINE= "$PY" manage.py dumpdata \
  --natural-foreign --natural-primary \
  -e contenttypes -e auth.permission \
  -e admin.logentry -e sessions.session \
  --indent 2 -o "$DUMP_FILE"

# --- 4. Schéma sur PostgreSQL ----------------------------------------------
log "migrate sur PostgreSQL (construction du schéma)"
DB_ENGINE=postgres "$PY" manage.py migrate --noinput

# --- 5. Import des données --------------------------------------------------
log "loaddata dans PostgreSQL"
DB_ENGINE=postgres "$PY" manage.py loaddata "$DUMP_FILE"

# --- 6. Réinitialisation des séquences d'auto-incrément ---------------------
log "sqlsequencereset ($SEQ_APPS)"
DB_ENGINE=postgres "$PY" manage.py sqlsequencereset $SEQ_APPS \
  | DB_ENGINE=postgres "$PY" manage.py dbshell

# --- 7. Comptage CIBLE (PostgreSQL) + contrôle de parité --------------------
log "Comptage des lignes côté PostgreSQL (cible)"
DST_COUNTS="$(DB_ENGINE=postgres count_rows)" || die "Comptage PG échoué."
echo "$DST_COUNTS"

log "Contrôle de parité SQLite vs PostgreSQL"
if [ "$SRC_COUNTS" = "$DST_COUNTS" ]; then
  printf '\033[1;32mPARITÉ OK : comptes identiques sur tous les modèles transférés.\033[0m\n'
else
  printf '\033[1;31mÉCART DÉTECTÉ (diff source -> cible) :\033[0m\n'
  diff <(echo "$SRC_COUNTS") <(echo "$DST_COUNTS") || true
  die "Parité NON respectée. NE PAS redémarrer sur PG. Investiguer le dump/load."
fi

# --- 8. Redémarrage ---------------------------------------------------------
if [ "$REHEARSE" = "0" ] && [ -n "$SERVICE" ]; then
  log "Redémarrage du service $SERVICE"
  sudo systemctl start "$SERVICE"
fi

log "Terminé. Effectuer les contrôles fonctionnels (Phase 4.2 du plan)."
