# shellcheck shell=bash
# Shared helpers for the repo's bash scripts.
# Source this file: `source "$(dirname "$0")/lib.sh"` (no shebang — not executable).

# Load environment variables from a .env file in the current directory.
# Usage: load_env [mode]
#   mode = "hard" (default): exit 1 with an error if .env is missing.
#   mode = "soft": set ENV_LOADED=0 and return 0 if .env is missing
#                  (ENV_LOADED=1 when it was loaded).
load_env() {
  local mode="${1:-hard}"

  if [ ! -f .env ]; then
    if [ "$mode" = "soft" ]; then
      ENV_LOADED=0
      return 0
    fi
    echo "❌ .env file not found!"
    exit 1
  fi

  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac   # skip blanks and comment lines
    key="${line%%=*}"
    val="${line#*=}"
    val="${val%\"}"; val="${val#\"}"            # strip one pair of surrounding quotes
    val="${val%\'}"; val="${val#\'}"
    export "$key=$val"
  done < .env

  ENV_LOADED=1
}

# Exit with an error if any of the named variables is empty.
# Usage: require_vars VAR1 VAR2 ...
require_vars() {
  local var
  for var in "$@"; do
    if [ -z "${!var}" ]; then
      echo "❌ Missing required variable: $var"
      exit 1
    fi
  done
}

# Exit with an error if the `db` container is not running.
require_db_running() {
  if [ -z "$(docker compose ps -q db)" ]; then
    echo "❌ The 'db' container is not running. Start it with: docker compose up -d"
    exit 1
  fi
}
