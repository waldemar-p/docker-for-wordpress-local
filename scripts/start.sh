#!/usr/bin/env bash
set -e

# Start the stack (port-aware) and, when run interactively, offer a setup wizard
# for the optional one-time steps (fix wp-config creds / import a DB / rewrite the
# site domain). Usage: ./scripts/start.sh [--no-wizard]   (run from project root)

# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

# .env is optional here — used for the SITE_HOST hint and the wizard's DB steps.
load_env soft

WIZARD=1
case "${1:-}" in --no-wizard) WIZARD=0 ;; esac

echo "🔌 Checking required host ports ..."
for port in $(compose_published_ports); do
  free_port "$port"
done

echo "🚀 Starting containers ..."
docker compose up -d

# An imported ./wordpress without core makes the image skip its copy → wp-cli and the
# browser both fail. Detect it now (rides out the first-boot copy) and offer to download.
ensure_wp_core || true

echo "📋 Current state:"
docker compose ps

echo "✅ Stack is up.${SITE_HOST:+ Visit: https://$SITE_HOST}"

# --- Setup wizard (interactive terminals only) -------------------------------
{ [ "$WIZARD" -eq 1 ] && [ -t 0 ]; } || exit 0

echo
read -r -p "Run the setup wizard (fix wp-config creds / import DB / rewrite domain)? [y/N] " go
case "$go" in [yY]|[yY][eE][sS]) ;; *) exit 0 ;; esac

DIR="$(dirname "$0")"

# 1) Fix wp-config.php DB credentials — needed when you brought your own ./wordpress.
if [ -f wordpress/wp-config.php ]; then
  read -r -p "  → Update wp-config.php DB credentials from .env? [y/N] " a
  case "$a" in [yY]|[yY][eE][sS]) "$DIR/update-wp-config.sh" ;; esac
fi

# 2) Import a database dump (waits for MySQL to be ready first).
read -r -p "  → Import a database dump now? [y/N] " a
case "$a" in
  [yY]|[yY][eE][sS])
    read -r -p "     SQL file [db.sql]: " f
    echo "     ⏳ Waiting for the database ..."
    if wait_for_db; then
      "$DIR/import-db.sh" "${f:-db.sql}"
    else
      echo "     ❌ Database not ready — skipped. Run ./scripts/import-db.sh later."
    fi
    ;;
esac

# 3) Rewrite the site domain in the DB to SITE_HOST.
read -r -p "  → Rewrite the site domain in the DB to ${SITE_HOST:-<SITE_HOST>}? [y/N] " a
case "$a" in
  [yY]|[yY][eE][sS])
    read -r -p "     Old domain to replace: " old
    if [ -z "$old" ]; then
      echo "     ↩️  No old domain given — skipped."
    elif wait_for_db; then
      "$DIR/update-db-domains.sh" "$old"
    else
      echo "     ❌ Database not ready — skipped. Run ./scripts/update-db-domains.sh later."
    fi
    ;;
esac

echo "🧙 Wizard complete."
