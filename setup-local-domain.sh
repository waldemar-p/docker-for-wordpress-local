#!/usr/bin/env bash
set -e

# Make a local domain resolve to and serve the WordPress container:
#   1. generate a host-level Nginx reverse-proxy config (-> http://localhost:8080)
#   2. register the domain(s) in /etc/hosts
#   3. install the config into system Nginx and reload it
#
# Usage: ./setup-local-domain.sh [url ...]
#   URLs default to LOCAL_URLS from .env when no arguments are given.

# Load environment variables from .env file (for the LOCAL_URLS fallback)
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

# Determine the URL list: CLI args take precedence, else LOCAL_URLS from .env
if [ "$#" -gt 0 ]; then
  URLS=("$@")
else
  # shellcheck disable=SC2206
  URLS=(${LOCAL_URLS})
fi

if [ "${#URLS[@]}" -eq 0 ]; then
  echo "❌ No URL given and LOCAL_URLS is empty in .env."
  echo "   Usage: ./setup-local-domain.sh <url> [more-urls...]"
  exit 1
fi

PRIMARY="${URLS[0]}"
CONF="${PRIMARY}.conf"
SERVER_NAMES="${URLS[*]}"

echo "⚙️  Generating Nginx config '$CONF' for: ${SERVER_NAMES}"

cat > "$CONF" <<EOF
server {
    listen 80;
    server_name ${SERVER_NAMES};

    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# Register each domain in /etc/hosts (idempotently)
echo "🧩 Updating /etc/hosts ..."
for url in "${URLS[@]}"; do
  if grep -qE "^\s*127\.0\.0\.1\s+${url}(\s|$)" /etc/hosts; then
    echo "   • $url already present, skipping"
  else
    echo "127.0.0.1   ${url}" | sudo tee -a /etc/hosts > /dev/null
    echo "   • added $url"
  fi
  if grep -qE "^\s*::1\s+${url}(\s|$)" /etc/hosts; then
    echo "   ⚠️  An IPv6 (::1) entry for '$url' exists in /etc/hosts — this can break the proxy. Consider removing it."
  fi
done

# Install into system Nginx and reload
echo "🚀 Installing config into system Nginx ..."
sudo cp "$CONF" "/etc/nginx/sites-available/$CONF"
sudo ln -sf "/etc/nginx/sites-available/$CONF" "/etc/nginx/sites-enabled/$CONF"

if sudo nginx -t; then
  sudo systemctl reload nginx
  echo "✅ Done. Visit: http://${PRIMARY}"
else
  echo "❌ 'nginx -t' failed — not reloading. Fix the config before retrying."
  echo "   Generated file kept at ./$CONF for inspection."
  exit 1
fi
