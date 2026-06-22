# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A minimal Docker Compose setup for running WordPress locally for development. The repo contains only the orchestration and config — **WordPress core, the database, and `.env` are gitignored** (`wordpress/`, `db/`, `.env`) and are created on first run.

## Architecture

Three services in `docker-compose.yaml`, all driven by variables from `.env`:

- **`wordpress`** — `wordpress:php8.2-fpm`. PHP-FPM only (no web server), listening on port 9000. Talks to `db:3306`.
- **`nginx`** — `nginx:latest`, exposed on host **`8080:80`**. Serves static files and reverse-proxies `*.php` to `wordpress:9000` via FastCGI. Config is `nginx.conf`, mounted read-only at `/etc/nginx/conf.d/default.conf`.
- **`db`** — `mysql:5.7`, exposed on host `3306:3306`.
- **`wpcli`** — `wordpress:cli`, behind the `cli` Compose profile so it never starts with `up -d`. It exists only to be invoked as a one-off via `docker compose run --rm wpcli wp <cmd>` (the `--rm` auto-removes the container); shares the `./wordpress` volume and the DB env. Used by `update-db-domains.sh`.

`wordpress` and `nginx` **share the same `./wordpress` bind mount** at `/var/www/html` — nginx needs the files on disk to serve static assets and resolve `SCRIPT_FILENAME`, while PHP-FPM executes them. The DB persists to `./db`.

Container names are templated as `${PROJECT_NAME}_wp`, `_nginx`, `_db`.

## First-time setup

```bash
cp .env.example .env          # then edit credentials + set LOCAL_URLS
docker compose up -d          # WordPress core auto-populates ./wordpress on first boot
./fill-wp-config-creds.sh     # inject .env credentials into wordpress/wp-config.php
```

`.env` also defines **`LOCAL_URLS`** — space-separated local domain(s) used as the default by
`setup-local-domain.sh` and `update-db-domains.sh` when no CLI args are passed.

`fill-wp-config-creds.sh` reads `.env`, requires `MYSQL_DATABASE`, `MYSQL_USER`, `MYSQL_PASSWORD`, and `WORDPRESS_TABLE_PREFIX`, creates `wp-config.php` from `wp-config-sample.php` if missing, then `sed`-replaces the `DB_*` defines (forcing `DB_HOST` to `db:3306`) and `$table_prefix`. It is idempotent — safe to re-run after changing `.env`.

## Common commands

```bash
docker compose up -d          # start
docker compose down           # stop (DB and WP files persist on disk)
docker compose logs -f nginx  # tail a service
docker compose exec db mysql -uroot -p${MYSQL_ROOT_PASSWORD} ${MYSQL_DATABASE}   # DB shell
```

Helper scripts (all root-level, match `fill-wp-config-creds.sh` style — load `.env`, validate, emoji status):

```bash
./import-db.sh [file.sql]              # import a dump (default: ./db.sql) into the db container
./setup-local-domain.sh [url...]       # /etc/hosts + host-Nginx reverse proxy + reload (default: LOCAL_URLS); uses sudo
./update-db-domains.sh <old> [new]     # rewrite domain in live DB via wp-cli, raw-SQL fallback (new default: first LOCAL_URLS)
./scan-wp-files.sh [dir]               # report-only: flag files/folders not part of a standard WP install (default: ./wordpress)
```

`scan-wp-files.sh` is hybrid and **report-only** (never deletes): Layer 1 is a self-contained
filesystem scan (whitelist of standard WP root entries flags unknown top-level files, plus
suspicious-pattern rules — PHP inside `wp-content/uploads/`, archives/`.sql` dumps, editor/VCS
junk); Layer 2 runs `docker compose run --rm wpcli wp core verify-checksums` when the `wordpress`
container is up, and is silently skipped otherwise.

`update-db-domains.sh` prefers wp-cli (`docker compose run --rm wpcli wp search-replace ...`) because it
rewrites serialized data correctly; it falls back to raw SQL `REPLACE` across `${prefix}options/posts/postmeta`
only if wp-cli can't run. For a dump from another domain, the raw `sed`-on-`.sql` approach (README §4) is the
pre-import alternative but does not handle serialized data.

Remember to update `DOMAIN_CURRENT_SITE` in `wp-config.php` if it's set (multisite).

## Notes

- Reaching the site via a clean domain (e.g. `http://mysite.local`) instead of `localhost:8080` is done with a **host-level Nginx reverse proxy** plus an `/etc/hosts` entry — that Nginx is separate from the `nginx` container. Avoid `::1` IPv6 host entries (they break the proxy). See README §1–2.
- The container `nginx.conf` hardcodes `server_name localhost` and proxies PHP to `wordpress:9000`; it is not the same file as the host reverse-proxy config shown in the README.
