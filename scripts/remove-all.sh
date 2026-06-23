#!/usr/bin/env bash
set -e

# Remove EVERYTHING for this project: containers, named volumes, and the on-disk
# state (./db and ./wordpress). DESTRUCTIVE — the database and all WordPress
# files are deleted. Usage: ./scripts/remove-all.sh [-y]   (run from project root)
#   -y / --yes : skip the confirmation prompt.

# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

# .env is optional here — only used to name the project in the output.
load_env soft

ASSUME_YES=0
case "${1:-}" in -y|--yes) ASSUME_YES=1 ;; esac

echo "⚠️  This will DELETE all state for this project${PROJECT_NAME:+ '$PROJECT_NAME'}:"
echo "    • containers + named volumes (docker compose down -v)"
echo "    • the database directory ./db"
echo "    • the WordPress files  ./wordpress"
if [ "$ASSUME_YES" -ne 1 ]; then
  read -r -p "Type 'yes' to proceed: " ans
  [ "$ans" = "yes" ] || { echo "↩️  Aborted — nothing removed."; exit 1; }
fi

echo "🛑 Removing containers and named volumes ..."
docker compose down -v --remove-orphans

# ./db and ./wordpress are created by the containers as root, so delete them via a
# throwaway container that has the privileges — avoids needing host sudo.
echo "🗑️  Deleting ./db and ./wordpress ..."
docker run --rm -v "$(pwd):/work" alpine sh -c 'rm -rf /work/db /work/wordpress'

echo "✅ All state removed (./db and ./wordpress are gone)."
