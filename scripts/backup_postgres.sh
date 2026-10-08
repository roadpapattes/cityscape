#!/usr/bin/env bash
#
# Sauvegarde quotidienne de CityScape : base PostgreSQL (pg_dump + gzip) ET
# fichiers déposés par les créateurs, avec rotation.
#
# Les deux sont indissociables : une base restaurée seule référencerait des
# images et des sons disparus, et toutes les escapes auraient leurs médias
# cassés. C'est le genre de manque qui ne se découvre qu'au pire moment.
#
# Lit les paramètres DB_* dans .env (mêmes valeurs que l'application).
# Prévu pour un cron quotidien (voir MIGRATION_POSTGRES.md, étape 6).
#
# Usage :
#   bash scripts/backup_postgres.sh
#   BACKUP_DIR=/srv/cityscape/backups RETENTION_DAYS=14 bash scripts/backup_postgres.sh
#
set -euo pipefail

APP_DIR="${APP_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
BACKUP_DIR="${BACKUP_DIR:-/srv/cityscape/backups}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"
ENV_FILE="${ENV_FILE:-$APP_DIR/.env}"
MEDIA_DIR="${MEDIA_DIR:-/var/www/cityscape/media}"

[ -f "$ENV_FILE" ] || { echo "ERREUR: $ENV_FILE introuvable" >&2; exit 1; }

# Lit une variable dans .env (dernière occurrence, tolère les espaces).
getenv() { grep -E "^[[:space:]]*$1=" "$ENV_FILE" | tail -1 | cut -d= -f2-; }

DB_NAME="$(getenv DB_NAME)"
DB_USER="$(getenv DB_USER)"
DB_PASSWORD="$(getenv DB_PASSWORD)"
DB_HOST="$(getenv DB_HOST)"; DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="$(getenv DB_PORT)"; DB_PORT="${DB_PORT:-5432}"

[ -n "$DB_NAME" ] || { echo "ERREUR: DB_NAME absent de $ENV_FILE" >&2; exit 1; }

mkdir -p "$BACKUP_DIR"
OUT="$BACKUP_DIR/cityscape-$(date +%F-%H%M).sql.gz"

# --clean --if-exists : le dump peut se restaurer sur une base existante.
PGPASSWORD="$DB_PASSWORD" pg_dump \
  -U "$DB_USER" -h "$DB_HOST" -p "$DB_PORT" \
  --clean --if-exists "$DB_NAME" | gzip > "$OUT"

# --- Médias déposés par les créateurs (images, fonds sonores) ---
# Horodatage identique au dump, pour qu'une base et ses fichiers se
# restaurent toujours par paire cohérente.
STAMP="$(basename "$OUT" .sql.gz)"
OUT_MEDIA="$BACKUP_DIR/${STAMP}-media.tar.gz"

if [ -d "$MEDIA_DIR" ]; then
  tar -czf "$OUT_MEDIA" -C "$(dirname "$MEDIA_DIR")" "$(basename "$MEDIA_DIR")"
  echo "Backup OK : $OUT_MEDIA ($(du -h "$OUT_MEDIA" | cut -f1))"
else
  # On ne fait pas echouer la sauvegarde de la base pour autant, mais le
  # message doit etre visible dans le journal.
  echo "ATTENTION : $MEDIA_DIR introuvable, medias NON sauvegardes" >&2
fi

# Rotation : supprime les sauvegardes plus vieilles que RETENTION_DAYS jours.
find "$BACKUP_DIR" -name 'cityscape-*.sql.gz' -type f -mtime "+$RETENTION_DAYS" -delete
find "$BACKUP_DIR" -name 'cityscape-*-media.tar.gz' -type f -mtime "+$RETENTION_DAYS" -delete

echo "Backup OK : $OUT ($(du -h "$OUT" | cut -f1))"
