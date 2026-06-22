#!/usr/bin/env bash
set -e

# Rewrite the site domain inside the LIVE database.
# Usage: ./update-db-domains.sh <old-domain> [new-domain]
#   new-domain defaults to the first entry of LOCAL_URLS in .env.
#
# Primary path uses wp-cli (serialized-data safe). If wp-cli can't run
# (e.g. WordPress core/files not present), it falls back to a raw SQL REPLACE.

# Load environment variables from .env file
if [ ! -f .env ]; then
  echo "❌ .env file not found!"
  exit 1
fi

export $(grep -v '^#' .env | xargs)

# Get required variables
REQUIRED_VARS=("MYSQL_ROOT_PASSWORD" "MYSQL_DATABASE" "WORDPRESS_TABLE_PREFIX")
for var in "${REQUIRED_VARS[@]}"; do
  if [ -z "${!var}" ]; then
    echo "❌ Missing required variable: $var"
    exit 1
  fi
done

OLD="$1"
# shellcheck disable=SC2206
NEW="${2:-$(set -- ${LOCAL_URLS}; echo "$1")}"

if [ -z "$OLD" ] || [ -z "$NEW" ]; then
  echo "❌ Usage: ./update-db-domains.sh <old-domain> [new-domain]"
  echo "   (new-domain defaults to the first entry of LOCAL_URLS in .env)"
  exit 1
fi

# Check the db container is running
if [ -z "$(docker compose ps -q db)" ]; then
  echo "❌ The 'db' container is not running. Start it with: docker compose up -d"
  exit 1
fi

PREFIX="$WORDPRESS_TABLE_PREFIX"

raw_sql_fallback() {
  echo "↩️  Falling back to raw SQL REPLACE (⚠️ may not fix serialized data — wp-cli is preferred)."
  docker compose exec -T db sh -c \
    'exec mysql -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"' <<SQL
UPDATE ${PREFIX}options    SET option_value = REPLACE(option_value, '${OLD}', '${NEW}');
UPDATE ${PREFIX}posts      SET post_content = REPLACE(post_content, '${OLD}', '${NEW}');
UPDATE ${PREFIX}posts      SET guid         = REPLACE(guid, '${OLD}', '${NEW}');
UPDATE ${PREFIX}postmeta   SET meta_value   = REPLACE(meta_value, '${OLD}', '${NEW}');
SQL
  echo "✅ Raw SQL replace complete."
}

echo "🔄 Rewriting domain '${OLD}' → '${NEW}' in database '${MYSQL_DATABASE}' ..."

# Primary path: wp-cli search-replace (handles serialized data correctly)
if docker compose run --rm wpcli \
     wp search-replace "$OLD" "$NEW" --all-tables --skip-columns=guid; then
  echo "✅ wp-cli search-replace complete."
else
  echo "⚠️  wp-cli search-replace failed (WordPress core may not be installed)."
  raw_sql_fallback
fi
