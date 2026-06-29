#!/usr/bin/env bash
set -e

# Remove state for this project: containers, named volumes, the database (./db),
# and OPTIONALLY the WordPress files (./wordpress — asked separately, kept by
# default). DESTRUCTIVE. Usage: ./scripts/remove-all.sh [-y]   (project root)
#   -y / --yes : skip all prompts and remove EVERYTHING, including ./wordpress.

# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname "$0")/lib.sh"

# .env is optional here — only used to name the project in the output.
load_env soft

ASSUME_YES=0
case "${1:-}" in -y|--yes) ASSUME_YES=1 ;; esac

REMOVE_WP=0
if [ "$ASSUME_YES" -eq 1 ]; then
  REMOVE_WP=1
else
  # shellcheck disable=SC2016  # $PROJECT_NAME expands; the single quotes are literal output
  echo "⚠️  This will DELETE state for this project${PROJECT_NAME:+ '$PROJECT_NAME'}:"
  echo "    • containers + named volumes (docker compose down -v)"
  echo "    • the database directory ./db"
  read -r -p "Type 'yes' to proceed: " ans
  [ "$ans" = "yes" ] || { echo "↩️  Aborted — nothing removed."; exit 1; }
  read -r -p "Also delete the WordPress files ./wordpress? [y/N] " wpans
  case "$wpans" in [yY]|[yY][eE][sS]) REMOVE_WP=1 ;; esac
fi

echo "🛑 Removing containers and named volumes ..."
docker compose down -v --remove-orphans

# ./db and ./wordpress are created by the containers as root, so delete them via a
# throwaway container that has the privileges — avoids needing host sudo.
if [ "$REMOVE_WP" -eq 1 ]; then
  echo "🗑️  Deleting ./db and ./wordpress ..."
  docker run --rm -v "$(pwd):/work" alpine sh -c 'rm -rf /work/db /work/wordpress'
  echo "✅ Removed containers, volumes, ./db and ./wordpress."
else
  echo "🗑️  Deleting ./db (keeping ./wordpress) ..."
  docker run --rm -v "$(pwd):/work" alpine sh -c 'rm -rf /work/db'
  echo "✅ Removed containers, volumes and ./db. Kept ./wordpress."
fi

# If start.sh stopped other services to claim host ports, our stack is down now so
# those ports are free again — restart whatever was stopped (recorded by free_port).
if [ -f "$PORT_RESTORE_FILE" ]; then
  echo
  echo "🔌 These services were stopped earlier to free host ports:"
  grep -v '^#' "$PORT_RESTORE_FILE" | sed 's/^/   • /'
  run_restore=1
  if [ "$ASSUME_YES" -ne 1 ]; then
    read -r -p "Restart them now? [Y/n] " r
    case "$r" in [nN]|[nN][oO]) run_restore=0 ;; esac
  fi
  if [ "$run_restore" -eq 1 ]; then
    bash "$PORT_RESTORE_FILE" && rm -f "$PORT_RESTORE_FILE" \
      && echo "✅ Restarted previously-stopped services."
  else
    echo "↩️  Left them stopped. Run '$PORT_RESTORE_FILE' yourself later, or delete it."
  fi
fi
