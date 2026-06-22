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

echo "✅ WordPress config ready in $WP_CONFIG."
