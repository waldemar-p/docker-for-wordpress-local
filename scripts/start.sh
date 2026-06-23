#!/usr/bin/env bash
set -e

# Start the stack: free any host ports we need to publish (e.g. 80/443 for
# Caddy), then `docker compose up -d`. Usage: ./scripts/start.sh   (project root)

# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

# .env is optional here — only used for the SITE_HOST hint in the final message.
load_env soft

echo "🔌 Checking required host ports ..."
for port in $(compose_published_ports); do
  free_port "$port"
done

echo "🚀 Starting containers ..."
docker compose up -d

echo "📋 Current state:"
docker compose ps

echo "✅ Stack is up.${SITE_HOST:+ Visit: https://$SITE_HOST}"
