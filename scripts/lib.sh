# shellcheck shell=bash
# Shared helpers for the repo's bash scripts.
# Source this file: `source "$(dirname "$0")/lib.sh"` (no shebang — not executable).

# Load environment variables from a .env file in the current directory.
# Usage: load_env [mode]
#   mode = "hard" (default): exit 1 with an error if .env is missing.
#   mode = "soft": set ENV_LOADED=0 and return 0 if .env is missing
#                  (ENV_LOADED=1 when it was loaded).
# shellcheck disable=SC2034,SC2120  # ENV_LOADED is read by callers; the mode arg is optional
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

# Wait until MySQL inside the db container accepts connections (~60s max).
# Returns 0 once ready, 1 on timeout. Useful right after `up` on first boot,
# when MySQL is still initialising.
wait_for_db() {
  for _ in $(seq 1 30); do
    if docker compose exec -T db sh -c \
         'exec mysqladmin ping -uroot -p"$MYSQL_ROOT_PASSWORD" --silent' >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  return 1
}

# uid:gid that owns ./wordpress, so a one-off wpcli container (whose default
# www-data differs from the php-fpm image's) can WRITE into the bind mount.
# ponytail: assumes a non-root owner; a root-owned tree would need --allow-root. GNU stat (Linux host).
wpcli_user() {
  [ -d wordpress ] && stat -c '%u:%g' wordpress 2>/dev/null || echo "33:33"
}

# Block until php-fpm is accepting connections inside the wordpress container. The
# official image's entrypoint copies core (if needed) and THEN execs php-fpm, so a
# listening :9000 is the deterministic "image finished its setup" signal — no arbitrary
# sleep. Returns 0 once ready, 1 on the failsafe timeout.
# ponytail: bash /dev/tcp probe (the wordpress image is Debian, has bash); the 60×1s is a
#   failsafe for a container that never comes up, not a fixed delay.
wait_for_wp_ready() {
  docker compose exec -T wordpress bash -c \
    'for i in $(seq 1 60); do (exec 3<>/dev/tcp/127.0.0.1/9000) 2>/dev/null && exit 0; sleep 1; done; exit 1'
}

# Carefully verify ./wordpress is a COMPLETE WordPress install before any wp-cli/DB step.
# Read-only: never downloads or modifies anything (we assume the supplied files should be
# complete and only check to be sure). Waits for the image to finish first, then checks
# the core bootstrap files plus the wp-admin/wp-includes dirs from the inside (so a missing
# or partial core dir is caught, not just version.php). On any miss, prints what's missing
# and returns 1; returns 0 when all present. wp-config.php is intentionally NOT required —
# the official image generates it, so requiring it would false-fail a fresh install.
check_wp_complete() {
  local dir="${1:-wordpress}"
  wait_for_wp_ready || echo "⚠️  wordpress container not ready — checking files anyway."

  local entry missing=""
  for entry in index.php wp-load.php wp-settings.php wp-blog-header.php \
               wp-admin wp-admin/index.php \
               wp-includes wp-includes/version.php wp-includes/functions.php \
               wp-content; do
    [ -e "$dir/$entry" ] || missing="$missing $entry"
  done

  [ -z "$missing" ] && return 0

  echo "❌ '$dir' is not a complete WordPress install."
  echo "   Missing:${missing}"
  echo "   Supply the files complete — the official image won't restore core when index.php"
  echo "   already exists, and these scripts never download WordPress."
  return 1
}

# Echo the unique host ports this compose project publishes (one per line).
compose_published_ports() {
  docker compose config 2>/dev/null \
    | awk '/published:/ { gsub(/[^0-9]/, "", $2); if ($2 != "") print $2 }' \
    | sort -un
}

# Return 0 if something is LISTENing on TCP $1, else 1.
port_in_use() {
  local port="$1"
  if command -v ss >/dev/null 2>&1; then
    [ -n "$(ss -ltnH "sport = :$port" 2>/dev/null)" ]
  elif command -v lsof >/dev/null 2>&1; then
    lsof -iTCP:"$port" -sTCP:LISTEN -n -P >/dev/null 2>&1
  else
    return 1   # no tool to check with — assume free
  fi
}

# A throwaway script free_port writes when it stops something to claim a port, so
# remove-all.sh can later restart whatever was stopped (put the ports back as they
# were). Lives in the project root; gitignored; deleted once consumed.
PORT_RESTORE_FILE=".restore-ports.sh"

# Append a restart command (the undo of a stop free_port just did) to the restore
# script, creating it with a header on first use. Deduplicates identical lines so
# repeated start.sh runs don't pile up.
record_port_restore() {
  local cmd="$1"
  if [ ! -f "$PORT_RESTORE_FILE" ]; then
    {
      echo "#!/usr/bin/env bash"
      echo "# Auto-generated by free_port (scripts/lib.sh). Restarts services that were"
      echo "# stopped to free host ports. remove-all.sh runs this; safe to run by hand."
    } > "$PORT_RESTORE_FILE"
  fi
  grep -qxF "$cmd" "$PORT_RESTORE_FILE" 2>/dev/null || echo "$cmd" >> "$PORT_RESTORE_FILE"
}

# If TCP $1 is occupied, identify what holds it (a Docker container, or a host
# process / systemd service) and OFFER to stop it. Always prompts; default No;
# never force-stops without approval. Call AFTER `docker compose down` so this
# project's own containers have already released their ports. Whatever it stops is
# recorded to $PORT_RESTORE_FILE so remove-all.sh can restart it later.
free_port() {
  local port="$1" ans
  port_in_use "$port" || return 0

  echo "⚠️  Port ${port} is already in use."

  # Case 1: another Docker container publishing this host port.
  local cname
  cname="$(docker ps --format '{{.Names}}\t{{.Ports}}' 2>/dev/null \
            | awk -v p="$port" '$0 ~ (":" p "->") { print $1; exit }')"
  if [ -n "$cname" ]; then
    read -r -p "   Stop Docker container '${cname}'? [y/N] " ans
    case "$ans" in
      [yY]|[yY][eE][sS])
        docker stop "$cname" >/dev/null \
          && { echo "   • stopped container '${cname}'"; record_port_restore "docker start '${cname}'"; } ;;
      *) echo "   ↩️  Left '${cname}' running — 'up' may fail to bind ${port}." ;;
    esac
    return 0
  fi

  # Case 2: a host process. Reading another user's PID from ss needs root.
  local pid
  pid="$(ss -ltnpH "sport = :$port" 2>/dev/null | grep -oE 'pid=[0-9]+' | head -1 | cut -d= -f2)"
  [ -z "$pid" ] && pid="$(sudo ss -ltnpH "sport = :$port" 2>/dev/null | grep -oE 'pid=[0-9]+' | head -1 | cut -d= -f2)"

  if [ -z "$pid" ]; then
    echo "   ❓ Couldn't identify the process on ${port}. Free it manually, then re-run."
    return 0
  fi

  local comm unit
  comm="$(ps -o comm= -p "$pid" 2>/dev/null)"
  # /proc/<pid>/cgroup is world-readable; the trailing .service is the systemd unit.
  unit="$(grep -oE '[a-zA-Z0-9@._-]+\.service' "/proc/$pid/cgroup" 2>/dev/null | grep -v '^docker\.service$' | head -1)"

  if [ -n "$unit" ]; then
    # Stopping the unit is safer than killing the PID (systemd would respawn it).
    read -r -p "   Stop service '${unit}' (process '${comm}', pid ${pid})? [y/N] " ans
    case "$ans" in
      [yY]|[yY][eE][sS])
        sudo systemctl stop "$unit" \
          && { echo "   • stopped service '${unit}'"; record_port_restore "sudo systemctl start '${unit}'"; } ;;
      *) echo "   ↩️  Left '${unit}' running — 'up' may fail to bind ${port}." ;;
    esac
  else
    read -r -p "   Kill process '${comm}' (pid ${pid})? [y/N] " ans
    case "$ans" in
      [yY]|[yY][eE][sS])
        sudo kill "$pid" \
          && { echo "   • killed pid ${pid} (${comm})"; record_port_restore "# killed pid ${pid} (${comm}) on a port — restart it manually"; } ;;
      *) echo "   ↩️  Left pid ${pid} running — 'up' may fail to bind ${port}." ;;
    esac
  fi
}
