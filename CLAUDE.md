# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A minimal Docker Compose setup for running WordPress locally for development. The repo contains only the orchestration and config — **WordPress core, the database, and `.env` are gitignored** (`wordpress/`, `db/`, `.env`) and are created on first run.

## Architecture

Four services in `docker-compose.yaml`, all driven by variables from `.env`:

- **`wordpress`** — `wordpress:php8.2-fpm`. PHP-FPM only (no web server), listening on port 9000. Talks to `db:3306`.
- **`nginx`** — `nginx:latest`, exposed on host **`8080:80`**. Serves static files and reverse-proxies `*.php` to `wordpress:9000` via FastCGI. Config is `nginx.conf`, mounted read-only at `/etc/nginx/conf.d/default.conf`.
- **`db`** — `mysql:5.7`, exposed on host `3306:3306`.
- **`wpcli`** — `wordpress:cli`, behind the `cli` Compose profile so it never starts with `up -d`. It exists only to be invoked as a one-off via `docker compose run --rm wpcli wp <cmd>` (the `--rm` auto-removes the container); shares the `./wordpress` volume and the DB env. Used by `update-db-domains.sh`.

`wordpress` and `nginx` **share the same `./wordpress` bind mount** at `/var/www/html` — nginx needs the files on disk to serve static assets and resolve `SCRIPT_FILENAME`, while PHP-FPM executes them. The DB persists to `./db`.

Container names are templated as `${PROJECT_NAME}_wp`, `_nginx`, `_db`.

## First-time setup

```bash
cp .env.example .env             # then edit credentials + set LOCAL_URLS
docker compose up -d             # WordPress core auto-populates ./wordpress on first boot
./scripts/fill-wp-config-creds.sh  # inject .env credentials into wordpress/wp-config.php
```

All helper scripts live in **`scripts/`** and must be **run from the project root** (e.g.
`./scripts/import-db.sh`) — they reference `.env`, `wordpress/`, `db.sql` and `docker compose`
relative to the current directory, not to the script's location.

`.env` also defines **`LOCAL_URLS`** — space-separated local domain(s) used as the default by
`setup-local-domain.sh` and `update-db-domains.sh` when no CLI args are passed.

`fill-wp-config-creds.sh` loads `.env` (via `load_env`) and requires `MYSQL_DATABASE`, `MYSQL_USER`, `MYSQL_PASSWORD`, and `WORDPRESS_TABLE_PREFIX` (via `require_vars`), creates `wp-config.php` from `wp-config-sample.php` if missing, then `sed`-replaces the `DB_*` defines (forcing `DB_HOST` to `db:3306`) and `$table_prefix`. It then injects (via `awk`, just before the `wp-settings.php` require) a reverse-proxy HTTPS-detection block that trusts `X-Forwarded-Proto` and sets `$_SERVER['HTTPS']` — without it, a site whose `siteurl`/`home` use `https://` redirect-loops forever behind the host Nginx proxy (which terminates TLS and forwards plain HTTP). The injection is guarded by a `grep` for `HTTP_X_FORWARDED_PROTO`, so the whole script stays idempotent — safe to re-run after changing `.env`.

## Common commands

```bash
docker compose up -d          # start
docker compose down           # stop (DB and WP files persist on disk)
docker compose logs -f nginx  # tail a service
docker compose exec db mysql -uroot -p${MYSQL_ROOT_PASSWORD} ${MYSQL_DATABASE}   # DB shell
```

Helper scripts (all in `scripts/`, same style — emoji status output) source shared helpers from `scripts/lib.sh`:

```bash
./scripts/import-db.sh [file.sql]            # import a dump (default: ./db.sql); if target DB has tables, prompts to drop+recreate (default No)
./scripts/setup-local-domain.sh [url...]     # /etc/hosts + host-Nginx http+https reverse proxy (self-signed cert via Docker) + reload (default: LOCAL_URLS); uses sudo
./scripts/update-db-domains.sh <old> [new]   # rewrite domain in live DB (wp-cli, raw-SQL fallback) + wp-config.php constants + report hard-coded hits (new default: first LOCAL_URLS)
./scripts/scan-wp-files.sh [dir]             # report-only: flag files/folders not part of a standard WP install (default: ./wordpress)
./scripts/recreate-containers.sh             # docker compose down --remove-orphans + up -d (wipes containers; ./db & ./wordpress persist)
```

`scripts/lib.sh` is **sourced, not executed** (no shebang). Each script begins with
`source "$(dirname "$0")/lib.sh"` and then calls its helpers instead of inlining the logic:

- `load_env [hard|soft]` — parse `.env` and `export` its vars (skips blanks/comments, strips one
  pair of surrounding quotes, keeps space-separated values like `LOCAL_URLS` intact). Default
  `hard` exits if `.env` is missing; `soft` instead sets `ENV_LOADED=0` and returns (used by
  `setup-local-domain.sh` and `scan-wp-files.sh`, where `.env` is optional). Sets `ENV_LOADED=1` on success.
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
only if wp-cli can't run. For a dump from another domain, the raw `sed`-on-`.sql` approach (README §4) is the
pre-import alternative but does not handle serialized data. After the DB rewrite it also updates any defined
`wp-config.php` constants (`WP_HOME`, `WP_SITEURL`, `DOMAIN_CURRENT_SITE`) via `wp config set` — so multisite
no longer needs a manual `DOMAIN_CURRENT_SITE` edit — and finally **reports** (does not edit) any literal
occurrences of the old domain hard-coded in `wp-content/` source files.

`setup-local-domain.sh` generates a vhost serving **both `http://` and `https://`**. For HTTPS it first
generates a self-signed cert (via a one-off `docker run --rm alpine/openssl` — no host openssl needed) into a
gitignored `certs/` dir (reused on re-runs), installs it to `/etc/nginx/certs/`, and references it from a
`listen 443 ssl` block. Without its own 443 vhost, `https://<domain>` falls through to whatever the host's
default TLS server is — frequently a 502. The script **prompts before overwriting** an existing
`/etc/nginx/sites-available/<domain>.conf`. The self-signed cert triggers a one-time browser warning;
trusting it (OS/browser trust store) is an optional manual step.

## Notes

- Reaching the site via a clean domain (e.g. `http://mysite.local`) instead of `localhost:8080` is done with a **host-level Nginx reverse proxy** plus an `/etc/hosts` entry — that Nginx is separate from the `nginx` container. Avoid `::1` IPv6 host entries (they break the proxy). See README §1–2.
- The container `nginx.conf` hardcodes `server_name localhost` and proxies PHP to `wordpress:9000`; it is not the same file as the host reverse-proxy config shown in the README.
