#!/usr/bin/env bash
set -e

# Import a SQL dump into the running `db` container.
# Usage: ./import-db.sh [file.sql]   (defaults to db.sql in this directory)

FILE="${1:-db.sql}"

# Load environment variables from .env file
if [ ! -f .env ]; then
  echo "❌ .env file not found!"
  exit 1
fi

export $(grep -v '^#' .env | xargs)

# Get required variables
REQUIRED_VARS=("MYSQL_ROOT_PASSWORD" "MYSQL_DATABASE")
for var in "${REQUIRED_VARS[@]}"; do
  if [ -z "${!var}" ]; then
    echo "❌ Missing required variable: $var"
    exit 1
  fi
done

# Check the dump file exists
if [ ! -f "$FILE" ]; then
  echo "❌ SQL file '$FILE' not found!"
  exit 1
fi

# Check the db container is running
if [ -z "$(docker compose ps -q db)" ]; then
  echo "❌ The 'db' container is not running. Start it with: docker compose up -d"
  exit 1
fi

echo "⛁  Importing '$FILE' into database '${MYSQL_DATABASE}' ..."

docker compose exec -T db sh -c \
  'exec mysql -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"' < "$FILE"

echo "✅ Import complete."
