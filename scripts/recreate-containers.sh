#!/usr/bin/env bash
set -e

# Cleanly stop and remove this project's containers, then recreate them.
# Container state is wiped for a fresh start; on-disk data is preserved
# (./db and ./wordpress are bind mounts, so MySQL data and WP files survive).
# Usage: ./scripts/recreate-containers.sh   (run from the project root)

# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

# .env is optional here — only used to name the project in the output.
load_env soft

echo "🛑 Stopping and removing containers${PROJECT_NAME:+ for '$PROJECT_NAME'} ..."
docker compose down --remove-orphans

echo "🚀 Recreating containers ..."
docker compose up -d

echo "📋 Current state:"
docker compose ps

echo "✅ Containers recreated. On-disk data in ./db and ./wordpress was preserved."
