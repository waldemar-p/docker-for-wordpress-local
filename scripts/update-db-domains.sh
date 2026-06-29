#!/usr/bin/env bash
set -e

# Rewrite the site domain inside the LIVE database.
# Usage: ./scripts/update-db-domains.sh <old-domain> [new-domain]   (run from the project root)
#   new-domain defaults to SITE_HOST in .env.
#
# Primary path uses wp-cli (serialized-data safe). If wp-cli can't run
# (e.g. WordPress core/files not present), it falls back to a raw SQL REPLACE.

# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

# Load environment variables from .env file
load_env

# Get required variables
require_vars MYSQL_ROOT_PASSWORD MYSQL_DATABASE WORDPRESS_TABLE_PREFIX

OLD="$1"
NEW="${2:-$SITE_HOST}"

if [ -z "$OLD" ] || [ -z "$NEW" ]; then
  echo "❌ Usage: ./scripts/update-db-domains.sh <old-domain> [new-domain]"
  echo "   (new-domain defaults to SITE_HOST in .env)"
  exit 1
fi

# Check the db container is running
require_db_running

# Make sure WordPress core is present, else wp-cli can't run (raw-SQL fallback only).
ensure_wp_core || true

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
  echo "⚠️  wp-cli ran but found no WordPress install at /var/www/html (core missing)."
  raw_sql_fallback
fi

# wp-config.php constants WordPress reads outside the DB (e.g. multisite, hard-set URLs).
# Only rewrite constants that are actually defined and contain the old domain.
echo "🧩 Checking wp-config.php constants ..."
for const in WP_HOME WP_SITEURL DOMAIN_CURRENT_SITE; do
  cur="$(docker compose run --rm wpcli wp config get "$const" 2>/dev/null)" || continue
  case "$cur" in
    *"$OLD"*)
      docker compose run --rm --user "$(wpcli_user)" wpcli wp config set "$const" "${cur//$OLD/$NEW}"
      echo "   • $const updated"
      ;;
  esac
done

# Literal occurrences on disk that wp-cli can't reach (theme/plugin source, page caches).
hits="$(docker compose run --rm wpcli sh -c "grep -rIl '$OLD' /var/www/html/wp-content 2>/dev/null" || true)"
if [ -n "$hits" ]; then
  echo "⚠️  '$OLD' also appears hard-coded in these files:"
  echo "$hits" | sed 's/^/   • /'

  # Offer to rewrite them too. Default No (editing source files is riskier than the
  # DB rewrite). Set REPLACE_FILES=1 to opt in non-interactively.
  do_replace=0
  case "${REPLACE_FILES:-}" in 1|yes|true|YES|TRUE) do_replace=1 ;; esac
  if [ "$do_replace" -eq 0 ] && [ -t 0 ]; then
    read -r -p "   Replace '$OLD' → '$NEW' in these files too? [y/N] " ans
    case "$ans" in [yY]|[yY][eE][sS]) do_replace=1 ;; esac
  fi

  if [ "$do_replace" -eq 1 ]; then
    echo "$hits" | docker compose run --rm -T --user "$(wpcli_user)" -e OLD="$OLD" -e NEW="$NEW" wpcli sh -c \
      'while IFS= read -r f; do [ -n "$f" ] && sed -i "s|$OLD|$NEW|g" "$f"; done'
    echo "   ✅ Replaced in $(echo "$hits" | grep -c .) file(s)."
  else
    echo "   ↩️  Left unchanged (review/replace manually)."
  fi
fi
