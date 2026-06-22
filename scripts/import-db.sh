#!/usr/bin/env bash
set -e

# Import a SQL dump into the running `db` container.
# Usage: ./scripts/import-db.sh [file.sql]   (run from the project root; defaults to db.sql there)

FILE="${1:-db.sql}"

# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

# Load environment variables from .env file
load_env

# Get required variables
require_vars MYSQL_ROOT_PASSWORD MYSQL_DATABASE

# Check the dump file exists
if [ ! -f "$FILE" ]; then
  echo "❌ SQL file '$FILE' not found!"
  exit 1
fi

# Check the db container is running
require_db_running

# If the target database already has tables, offer to drop it first so the
# import starts from a clean slate (a dump won't remove tables it doesn't define).
TABLE_COUNT=$(docker compose exec -T db sh -c \
  'exec mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -N -B -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = \"$MYSQL_DATABASE\";"' </dev/null)

if [ "${TABLE_COUNT:-0}" -gt 0 ]; then
  printf "⚠️  Database '%s' already exists with %s table(s).\n" "${MYSQL_DATABASE}" "$TABLE_COUNT"
  read -r -p "   Drop it before importing? [y/N] " reply
  case "$reply" in
    [yY]|[yY][eE][sS])
      echo "🗑️  Dropping and recreating database '${MYSQL_DATABASE}' ..."
      docker compose exec -T db sh -c \
        'exec mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "DROP DATABASE IF EXISTS \`$MYSQL_DATABASE\`; CREATE DATABASE \`$MYSQL_DATABASE\`;"' </dev/null
      ;;
    *)
      echo "↪️  Keeping existing database; importing on top of it."
      ;;
  esac
fi

echo "⛁  Importing '$FILE' into database '${MYSQL_DATABASE}' ..."

docker compose exec -T db sh -c \
  'exec mysql -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"' < "$FILE"

echo "✅ Import complete."
