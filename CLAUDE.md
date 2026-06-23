# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A minimal Docker Compose setup for running WordPress locally for development, reachable over a clean
`https://<name>.localhost` domain with no host web server, no `/etc/hosts` edits, and no manual
certificate handling. The repo contains only the orchestration and config — **WordPress core, the
database, and `.env` are gitignored** (`wordpress/`, `db/`, `.env`) and are created on first run.

## Architecture

Three services in `docker-compose.yaml` (plus a profile-gated wp-cli runner), all driven by
variables from `.env`:

- **`wordpress`** — `wordpress:php8.2-fpm`. PHP-FPM only (no web server), listening on port 9000.
  Talks to `db:3306`. The official image **auto-generates `wordpress/wp-config.php`** on first boot
  from the `WORDPRESS_*` environment variables, so there is no manual credential-injection step.
- **`caddy`** — `caddy:2`, the web server, exposed on host **`80`** and **`443`**. Serves static
  files from the shared `./wordpress` mount, proxies `*.php` to `wordpress:9000` via FastCGI
  (`php_fastcgi`), and provides **automatic local HTTPS** via its own internal CA. Config is
  `Caddyfile`, mounted read-only at `/etc/caddy/Caddyfile`. Caddy's CA/cert state persists in the
  named volumes `caddy_data` / `caddy_config`.
- **`db`** — `mysql:5.7`, exposed on host `3306:3306`.
- **`wpcli`** — `wordpress:cli`, behind the `cli` Compose profile so it never starts with `up -d`.
  Invoked as a one-off via `docker compose run --rm wpcli wp <cmd>` (`--rm` auto-removes the
  container); shares the `./wordpress` volume and the DB env. Used by `update-db-domains.sh`.

`wordpress` and `caddy` **share the same `./wordpress` bind mount** at `/var/www/html` — Caddy needs
the files on disk to serve static assets and resolve `SCRIPT_FILENAME`, while PHP-FPM executes them.
The DB persists to `./db`. Container names are templated as `${PROJECT_NAME}_wp`, `_caddy`, `_db`.

### Clean domain + HTTPS (why there is no host Nginx)

- A host ending in **`.localhost`** resolves to `127.0.0.1` automatically in Chromium browsers and
  Safari (RFC 6761) — no `/etc/hosts` entry. `.env`'s **`SITE_HOST`** sets which domain Caddy serves
  (default `wpproject.localhost`), referenced in the `Caddyfile` as `{$SITE_HOST:wpproject.localhost}`.
- The `Caddyfile`'s global `local_certs` directive forces Caddy's internal CA for any host, so a
  private domain gets a locally-trusted cert instead of a failed public Let's Encrypt issuance.
- Because Caddy terminates TLS *and* serves PHP over FastCGI itself, WordPress sees `HTTPS=on`
  natively — no redirect loops. (The official image's generated `wp-config.php` also trusts
  `X-Forwarded-Proto` out of the box, so reverse-proxy HTTPS detection needs no manual config.)
- To remove the one-time browser warning for Caddy's local CA: `docker compose exec caddy caddy trust`.

## First-time setup

```bash
cp .env.example .env             # then edit credentials + set SITE_HOST
docker compose up -d             # WordPress core + wp-config.php auto-populate on first boot
```

Open `https://<SITE_HOST>`. Ports 80/443 must be free — stop any host-level Nginx/Apache first.

All helper scripts live in **`scripts/`** and must be **run from the project root** (e.g.
`./scripts/import-db.sh`) — they reference `.env`, `wordpress/`, `db.sql` and `docker compose`
relative to the current directory, not to the script's location.

`.env` defines **`SITE_HOST`** — the local domain used by Caddy and as the default `new` domain for
`update-db-domains.sh`.

## Common commands

```bash
docker compose up -d          # start
docker compose down           # stop (DB and WP files persist on disk)
docker compose logs -f caddy  # tail a service
docker compose exec caddy caddy trust   # trust the local HTTPS cert (one-time, optional)
docker compose exec db mysql -uroot -p${MYSQL_ROOT_PASSWORD} ${MYSQL_DATABASE}   # DB shell
```

Helper scripts (all in `scripts/`, same style — emoji status output) source shared helpers from `scripts/lib.sh`:

```bash
./scripts/import-db.sh [file.sql]            # import a dump (default: ./db.sql); if target DB has tables, prompts to drop+recreate (default No)
./scripts/update-db-domains.sh <old> [new]   # rewrite domain in live DB (wp-cli, raw-SQL fallback) + wp-config.php constants + report hard-coded hits (new default: SITE_HOST)
./scripts/scan-wp-files.sh [dir]             # report-only: flag files/folders not part of a standard WP install (default: ./wordpress)
./scripts/recreate-containers.sh             # docker compose down --remove-orphans + up -d (wipes containers; ./db & ./wordpress persist)
```

`scripts/lib.sh` is **sourced, not executed** (no shebang). Each script begins with
`source "$(dirname "$0")/lib.sh"` and then calls its helpers instead of inlining the logic:

- `load_env [hard|soft]` — parse `.env` and `export` its vars (skips blanks/comments, strips one
  pair of surrounding quotes). Default `hard` exits if `.env` is missing; `soft` instead sets
  `ENV_LOADED=0` and returns (used by `scan-wp-files.sh`, where `.env` is optional). Sets
  `ENV_LOADED=1` on success.
- `require_vars VAR...` — exit with `❌ Missing required variable` if any named var is empty.
- `require_db_running` — exit if the `db` container isn't up.

`scan-wp-files.sh` is hybrid and **report-only** (never deletes): Layer 1 is a self-contained
filesystem scan (whitelist of standard WP root entries flags unknown top-level files, plus
suspicious-pattern rules — PHP inside `wp-content/uploads/`, archives/`.sql` dumps, editor/VCS
junk); Layer 2 runs `docker compose run --rm wpcli wp core verify-checksums` when the `wordpress`
container is up, and is silently skipped otherwise. A lone `wp-config-sample.php` checksum
mismatch (and the resulting "doesn't verify against checksums" error) is **expected** — the
official WordPress Docker image ships a slightly modified sample file; the script prints a note
saying so. Only mismatches under `wp-admin/`/`wp-includes/` or unexpected extra files matter.

`update-db-domains.sh` prefers wp-cli (`docker compose run --rm wpcli wp search-replace ...`) because it
rewrites serialized data correctly; it falls back to raw SQL `REPLACE` across `${prefix}options/posts/postmeta`
only if wp-cli can't run. For a dump from another domain, the raw `sed`-on-`.sql` approach (README) is the
pre-import alternative but does not handle serialized data. After the DB rewrite it also updates any defined
`wp-config.php` constants (`WP_HOME`, `WP_SITEURL`, `DOMAIN_CURRENT_SITE`) via `wp config set` — so multisite
no longer needs a manual `DOMAIN_CURRENT_SITE` edit — and finally **reports** (does not edit) any literal
occurrences of the old domain hard-coded in `wp-content/` source files.

## Notes

- Reaching the site via a clean domain is done purely by the `caddy` container + the `.localhost`
  TLD — there is **no host-level web server** and **no `/etc/hosts` entry** involved. A non-`.localhost`
  TLD (e.g. `.test`) would require a manual `/etc/hosts` line.
- The `Caddyfile` hardcodes the `php_fastcgi wordpress:9000` upstream and serves `root /var/www/html`;
  the served domain comes from `SITE_HOST`.
