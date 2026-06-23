#!/usr/bin/env bash
set -e

# Full reset to a clean slate: remove ALL state (containers, volumes, ./db,
# ./wordpress) and then start the stack fresh. Thin wrapper that just runs
# remove-all.sh then start.sh. Usage: ./scripts/reset-state.sh [-y]   (project root)
#   -y / --yes : skip remove-all.sh's confirmation prompt.

DIR="$(dirname "$0")"

"$DIR/remove-all.sh" "$@"
"$DIR/start.sh"

echo "♻️  Reset complete — fresh WordPress core and an empty database."
