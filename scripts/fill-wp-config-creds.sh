#!/usr/bin/env bash
set -e

WP_DIR="wordpress"

# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

# Load environment variables from .env file
load_env

# Get required variables
require_vars MYSQL_DATABASE MYSQL_USER MYSQL_PASSWORD WORDPRESS_TABLE_PREFIX

# Check if wordpress folder exists
if [ ! -d "$WP_DIR" ]; then
  echo "❌ WordPress folder '$WP_DIR' not found!"
  exit 1
fi

WP_CONFIG="$WP_DIR/wp-config.php"
WP_SAMPLE="$WP_DIR/wp-config-sample.php"

# If wp-config.php doesn't exist, copy from sample
if [ ! -f "$WP_CONFIG" ]; then
  echo "📄 No wp-config.php found — creating from sample..."
  if [ ! -f "$WP_SAMPLE" ]; then
    echo "❌ wp-config-sample.php not found!"
    exit 1
  fi
  cp "$WP_SAMPLE" "$WP_CONFIG"
fi

echo "⚙️  Configuring wp-config.php ..."

sed -i "s@define(\s*['\"]DB_NAME['\"],\s*['\"].*['\"]\s*);@define( 'DB_NAME', '${MYSQL_DATABASE}' );@" "$WP_CONFIG"
sed -i "s@define(\s*['\"]DB_USER['\"],\s*['\"].*['\"]\s*);@define( 'DB_USER', '${MYSQL_USER}' );@" "$WP_CONFIG"
sed -i "s@define(\s*['\"]DB_PASSWORD['\"],\s*['\"].*['\"]\s*);@define( 'DB_PASSWORD', '${MYSQL_PASSWORD}' );@" "$WP_CONFIG"
sed -i "s@define(\s*['\"]DB_HOST['\"],\s*['\"].*['\"]\s*);@define( 'DB_HOST', 'db:3306' );@" "$WP_CONFIG"

# Update table prefix
sed -i "s@^\$table_prefix\s*=\s*['\"].*\s*;@\$table_prefix = '${WORDPRESS_TABLE_PREFIX}';@" "$WP_CONFIG"

# Trust the host reverse proxy's X-Forwarded-Proto header. The host Nginx
# terminates TLS and forwards plain HTTP to this container, so without this
# WordPress can't tell the request was HTTPS and redirects HTTP->HTTPS forever
# (an endless loop) whenever siteurl/home use https. Idempotent via the grep.
if ! grep -q "HTTP_X_FORWARDED_PROTO" "$WP_CONFIG"; then
  echo "🔒 Adding reverse-proxy HTTPS detection ..."
  PROXY_BLOCK="$(cat <<'PHP'

/* Behind the host Nginx reverse proxy, TLS terminates there and the request
 * reaches this container over plain HTTP. Trust X-Forwarded-Proto so WordPress
 * knows the request was HTTPS — otherwise it redirects HTTP->HTTPS endlessly. */
if ( isset( $_SERVER['HTTP_X_FORWARDED_PROTO'] ) && 'https' === $_SERVER['HTTP_X_FORWARDED_PROTO'] ) {
	$_SERVER['HTTPS'] = 'on';
}
PHP
)"
  awk -v block="$PROXY_BLOCK" '
    /wp-settings\.php/ && !done { print block; done = 1 }
    { print }
  ' "$WP_CONFIG" > "$WP_CONFIG.tmp" && mv "$WP_CONFIG.tmp" "$WP_CONFIG"
fi

echo "✅ WordPress config ready in $WP_CONFIG."
