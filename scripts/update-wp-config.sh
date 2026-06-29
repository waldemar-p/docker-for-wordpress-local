#!/usr/bin/env bash
set -e

# Update DB credentials, table prefix and DB host in an EXISTING
# wordpress/wp-config.php to match .env. Needed when you bring your own
# ./wordpress (e.g. a migrated site) whose wp-config.php still points at another
# host's database: the official WordPress image only auto-generates wp-config.php
# when it is MISSING, so an imported one keeps its stale credentials.
# On a fresh, image-generated wp-config.php (which reads creds from the
# environment) the replacements simply don't match — so this is a safe no-op there.
# Usage: ./scripts/update-wp-config.sh   (run from the project root)

# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname "$0")/lib.sh"

load_env
require_vars MYSQL_DATABASE MYSQL_USER MYSQL_PASSWORD WORDPRESS_TABLE_PREFIX

WP_CONFIG="wordpress/wp-config.php"

if [ ! -f "$WP_CONFIG" ]; then
  echo "ℹ️  No $WP_CONFIG yet — the WordPress image generates it from .env on first"
  echo "   boot, so there's nothing to update. Start the stack first (./scripts/start.sh)."
  exit 0
fi

echo "⚙️  Updating DB credentials in $WP_CONFIG from .env ..."
sed -i "s@define(\s*['\"]DB_NAME['\"],\s*['\"].*['\"]\s*);@define( 'DB_NAME', '${MYSQL_DATABASE}' );@"         "$WP_CONFIG"
sed -i "s@define(\s*['\"]DB_USER['\"],\s*['\"].*['\"]\s*);@define( 'DB_USER', '${MYSQL_USER}' );@"             "$WP_CONFIG"
sed -i "s@define(\s*['\"]DB_PASSWORD['\"],\s*['\"].*['\"]\s*);@define( 'DB_PASSWORD', '${MYSQL_PASSWORD}' );@" "$WP_CONFIG"
sed -i "s@define(\s*['\"]DB_HOST['\"],\s*['\"].*['\"]\s*);@define( 'DB_HOST', 'db:3306' );@"                   "$WP_CONFIG"
sed -i "s@^\$table_prefix\s*=\s*['\"].*\s*;@\$table_prefix = '${WORDPRESS_TABLE_PREFIX}';@"                    "$WP_CONFIG"

echo "✅ Done — DB creds set from .env, DB_HOST forced to db:3306, prefix '${WORDPRESS_TABLE_PREFIX}'."
echo "   (No container restart needed; PHP reads wp-config.php on each request.)"
