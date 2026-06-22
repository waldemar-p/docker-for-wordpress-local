#!/usr/bin/env bash
set -e

# Import a SQL dump into the running `db` container.
# Usage: ./import-db.sh [file.sql]   (defaults to db.sql in this directory)

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

echo "⛁  Importing '$FILE' into database '${MYSQL_DATABASE}' ..."

docker compose exec -T db sh -c \
  'exec mysql -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"' < "$FILE"

echo "✅ Import complete."
