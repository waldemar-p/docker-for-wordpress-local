#!/usr/bin/env bash
set -e

# Scan the WordPress folder and REPORT files/folders that are probably not part of
# a standard WordPress install (cruft, leftover dumps, editor junk, injected PHP).
# Usage: ./scripts/scan-wp-files.sh [dir]   (run from the project root; dir defaults to ./wordpress)
#
# Nothing is ever deleted or moved.
# Layer 0 (FATAL): structural completeness gate — if core is missing/incomplete, report
#   what's missing and exit non-zero (so a caller like start.sh can abort + tear down).
# Layer 1 (report): filesystem heuristics — unknown root entries + suspicious patterns.
# Layer 2 (report): `wp core verify-checksums` via wp-cli, when the containers are up.
# The full output is also written to a report file (WP_SCAN_REPORT, default
# ./wp-scan-report.txt) via tee.

WP_DIR="${1:-wordpress}"

# Mirror the whole run (incl. the docker checksum output) to a report file and the
# terminal. Re-exec once through tee; PIPESTATUS propagates the real exit code so a
# caller (start.sh) still sees a Layer 0 abort.
REPORT="${WP_SCAN_REPORT:-wp-scan-report.txt}"
if [ -z "${SCAN_TEEING:-}" ]; then
  SCAN_TEEING=1 "$0" "$@" 2>&1 | tee "$REPORT"
  rc="${PIPESTATUS[0]}"
  echo "📄 Scan report saved to $REPORT"
  exit "$rc"
fi

if [ ! -d "$WP_DIR" ]; then
  echo "❌ WordPress folder '$WP_DIR' not found. Run 'docker compose up -d' first."
  exit 1
fi

# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname "$0")/lib.sh"

# Load .env (only needed to enable the optional wp-cli layer) — soft guard.
load_env soft

# --- Layer 0: structural completeness gate (FATAL) -----------------------------
# A complete core is a precondition for everything below; abort here on failure so
# callers (start.sh) can tear the stack down rather than scan a broken install.
check_wp_complete "$WP_DIR" || exit 1

declare -A FLAGGED                  # relative path -> 1 (dedups items flagged twice)

echo "🔎 Scanning '$WP_DIR' for files not part of a standard WordPress install ..."

# --- Layer 1a: unknown top-level entries ---------------------------------------
# Standard WordPress root entries (plus WP-generated .htaccess / .maintenance).
WP_STD=(
  index.php license.txt readme.html xmlrpc.php
  wp-activate.php wp-blog-header.php wp-comments-post.php wp-cron.php
  wp-links-opml.php wp-load.php wp-login.php wp-mail.php
  wp-settings.php wp-signup.php wp-trackback.php
  wp-config.php wp-config-sample.php
  wp-admin wp-includes wp-content
  .htaccess .maintenance
)

is_standard() {
  local name="$1"
  for std in "${WP_STD[@]}"; do
    [ "$name" = "$std" ] && return 0
  done
  return 1
}

UNKNOWN=()
for path in "$WP_DIR"/* "$WP_DIR"/.[!.]*; do
  [ -e "$path" ] || continue          # skip when a glob matches nothing
  name="$(basename "$path")"
  if ! is_standard "$name"; then
    UNKNOWN+=("$name")
  fi
done

if [ "${#UNKNOWN[@]}" -gt 0 ]; then
  echo ""
  echo "⚠️  Unknown top-level entries (not standard WordPress):"
  for name in "${UNKNOWN[@]}"; do
    echo "   • $name"
    FLAGGED["$name"]=1
  done
fi

# --- Layer 1b: suspicious patterns (recursive) ---------------------------------
report_find() {
  # $1 = heading; find results read from stdin (run in the main shell via
  # process substitution so FLAGGED increments survive).
  local heading="$1"
  local found=0 rel
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    if [ "$found" -eq 0 ]; then
      echo ""
      echo "$heading"
      found=1
    fi
    rel="${line#"$WP_DIR"/}"
    echo "   • $rel"
    FLAGGED["$rel"]=1
  done
}

# PHP inside uploads — uploads should never contain executable PHP (backdoor signal).
if [ -d "$WP_DIR/wp-content/uploads" ]; then
  report_find "🚨 PHP files inside wp-content/uploads (possible backdoor):" \
    < <(find "$WP_DIR/wp-content/uploads" -type f -name '*.php')
fi

# Archives / DB dumps / swap files anywhere.
report_find "⚠️  Archives / database dumps / swap files:" < <(find "$WP_DIR" -type f \( \
  -name '*.zip' -o -name '*.tar' -o -name '*.tar.gz' -o -name '*.tgz' \
  -o -name '*.gz' -o -name '*.rar' -o -name '*.7z' -o -name '*.sql' \
  -o -name '*.bak' -o -name '*.old' -o -name '*.orig' -o -name '*.save' \
  -o -name '*.swp' -o -name '*.swo' \
  \))

# Editor / OS / VCS junk.
report_find "⚠️  Editor / OS / VCS junk:" < <(find "$WP_DIR" \( \
  -type f \( -name '.DS_Store' -o -name 'Thumbs.db' -o -name '*~' \) \
  -o -type d \( -name '.git' -o -name '.svn' \) \
  \))

# --- Layer 2: wp-cli checksums (optional) --------------------------------------
echo ""
if [ "$ENV_LOADED" -eq 0 ]; then
  echo "⚙️  wp-cli checksum layer skipped (.env not found)."
elif [ -z "$(docker compose ps -q wordpress 2>/dev/null)" ]; then
  echo "⚙️  wp-cli checksum layer skipped (the 'wordpress' container is not running)."
else
  echo "⚙️  Verifying WordPress core checksums via wp-cli ..."
  set +e
  docker compose run --rm wpcli wp core verify-checksums
  set -e
  echo "   ℹ️  A lone 'wp-config-sample.php' mismatch (and the resulting \"doesn't verify\""
  echo "      against checksums\" error) is expected — the official WordPress Docker image"
  echo "      ships a slightly modified sample file. Mismatches under wp-admin/ or"
  echo "      wp-includes/, or unexpected extra files, are the ones worth investigating."
fi

# --- Summary -------------------------------------------------------------------
echo ""
echo "✅ Scan complete — ${#FLAGGED[@]} item(s) flagged by filesystem heuristics."
echo "   Nothing was deleted; review the list above manually."
