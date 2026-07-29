#!/usr/bin/env bash
#
# Sauvegarde quotidienne de la base PostgreSQL de CityScape (pg_dump + gzip),
# avec rotation. Remplace l'ancienne copie de db.sqlite3.
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

# Rotation : supprime les sauvegardes plus vieilles que RETENTION_DAYS jours.
find "$BACKUP_DIR" -name 'cityscape-*.sql.gz' -type f -mtime "+$RETENTION_DAYS" -delete

echo "Backup OK : $OUT ($(du -h "$OUT" | cut -f1))"
