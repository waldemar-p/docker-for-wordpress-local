#!/usr/bin/env bash
set -e

# Make a local domain resolve to and serve the WordPress container:
#   1. generate a self-signed cert (via Docker) and a host-level Nginx reverse-proxy
#      config serving both http:// and https:// (-> http://localhost:8080)
#   2. register the domain(s) in /etc/hosts
#   3. install the config + cert into system Nginx and reload it
#
# Usage: ./scripts/setup-local-domain.sh [url ...]   (run from the project root)
#   URLs default to LOCAL_URLS from .env when no arguments are given.

# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

# Load environment variables from .env file (for the LOCAL_URLS fallback)
load_env soft

# Determine the URL list: CLI args take precedence, else LOCAL_URLS from .env
if [ "$#" -gt 0 ]; then
  URLS=("$@")
else
  # shellcheck disable=SC2206
  URLS=(${LOCAL_URLS})
fi

if [ "${#URLS[@]}" -eq 0 ]; then
  echo "❌ No URL given and LOCAL_URLS is empty in .env."
  echo "   Usage: ./scripts/setup-local-domain.sh <url> [more-urls...]"
  exit 1
fi

PRIMARY="${URLS[0]}"
CONF="${PRIMARY}.conf"
SERVER_NAMES="${URLS[*]}"
CERT="${PRIMARY}.pem"
KEY="${PRIMARY}-key.pem"

# Generate a self-signed cert (once) so the domain has its own HTTPS vhost — otherwise
# https://${PRIMARY} falls through to whatever the default 443 server is (often → 502).
# openssl is provided via Docker so nothing has to be installed on the host.
if [ ! -f "certs/$CERT" ] || [ ! -f "certs/$KEY" ]; then
  echo "🔐 Generating self-signed certificate for: ${SERVER_NAMES} (via Docker openssl) ..."
  mkdir -p certs
  SAN="$(printf 'DNS:%s,' "${URLS[@]}" | sed 's/,$//')"
  docker run --rm -v "$(pwd)/certs:/certs" alpine/openssl req -x509 -nodes \
    -newkey rsa:2048 -days 825 \
    -keyout "/certs/$KEY" -out "/certs/$CERT" \
    -subj "/CN=${PRIMARY}" -addext "subjectAltName=${SAN}"
else
  echo "🔐 Reusing existing certificate at certs/$CERT"
fi

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

server {
    listen 443 ssl http2;
    server_name ${SERVER_NAMES};

    ssl_certificate     /etc/nginx/certs/${CERT};
    ssl_certificate_key /etc/nginx/certs/${KEY};

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
if [ -e "/etc/nginx/sites-available/$CONF" ]; then
  read -r -p "⚠️  /etc/nginx/sites-available/$CONF already exists. Overwrite? [y/N] " ans
  case "$ans" in
    [yY]) ;;
    *) echo "↩️  Keeping existing config; aborting."; exit 1 ;;
  esac
fi

# Install the cert where the root-owned nginx can always read it.
sudo mkdir -p /etc/nginx/certs
sudo cp "certs/$CERT" "certs/$KEY" /etc/nginx/certs/

sudo cp "$CONF" "/etc/nginx/sites-available/$CONF"
sudo ln -sf "/etc/nginx/sites-available/$CONF" "/etc/nginx/sites-enabled/$CONF"

if sudo nginx -t; then
  sudo systemctl reload nginx
  echo "✅ Done. Visit: https://${PRIMARY}  (http:// works too)"
  echo "   ℹ️  The cert is self-signed, so the browser shows a one-time warning. To trust it"
  echo "      without warnings you'd add certs/$CERT to your OS/browser trust store (manual)."
else
  echo "❌ 'nginx -t' failed — not reloading. Fix the config before retrying."
  echo "   Generated file kept at ./$CONF for inspection."
  exit 1
fi
