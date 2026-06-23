#!/usr/bin/env bash
set -e

# Full reset to a clean slate: remove ALL state (containers, volumes, ./db and
# ./wordpress) and then start the stack fresh. Thin wrapper over remove-all.sh +
# start.sh. Usage: ./scripts/reset-state.sh [-y]   (run from the project root)
#   -y / --yes : skip remove-all.sh's confirmation AND start.sh's wizard.

DIR="$(dirname "$0")"

"$DIR/remove-all.sh" "$@"

# With -y (non-interactive intent), skip start.sh's wizard too.
case " $* " in
  *" -y "*|*" --yes "*) "$DIR/start.sh" --no-wizard ;;
  *) "$DIR/start.sh" ;;
esac

echo "♻️  Reset complete — fresh WordPress core and an empty database."
