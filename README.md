
# Local Docker WordPress

A minimal Docker Compose setup for running WordPress locally over a clean
`https://<name>.localhost` domain — **no host web server, no `/etc/hosts` edits, no manual certs.**

## ⚡ TL;DR — quick start

```bash
cp .env.example .env                 # then edit credentials, PROJECT_NAME, SITE_HOST
docker compose up -d                 # boot; WordPress core + wp-config.php auto-populate
```

Open **`https://wpproject.localhost`** (or whatever you set `SITE_HOST` to).

```bash
# Optional — restore an existing site from a dump:
./scripts/import-db.sh db.sql            # import ./db.sql (set WORDPRESS_TABLE_PREFIX to match it first!)
./scripts/update-db-domains.sh old.com   # rewrite domain → SITE_HOST
```

> All helper scripts live in `scripts/` — run them **from the project root** (as shown above).

---

## How it works

Three containers (plus a one-off wp-cli runner), all driven by `.env`:

- **`wordpress`** — `wordpress:php8.2-fpm`. PHP-FPM only, on port 9000. The official image
  **auto-generates `wordpress/wp-config.php`** from the `WORDPRESS_*` env vars on first boot — no
  manual credential step.
- **`caddy`** — `caddy:2`, the web server. Serves static files, proxies PHP via FastCGI to
  `wordpress:9000`, and terminates **automatic local HTTPS**. Listens on host ports **80** and **443**.
- **`db`** — `mysql:5.7`, on host `3306`.
- **`wpcli`** — `wordpress:cli`, behind the `cli` profile (never starts with `up -d`); used by the
  helper scripts via `docker compose run --rm wpcli wp <cmd>`.

**Clean domain with zero config:** a host ending in `.localhost` resolves to `127.0.0.1`
automatically in Chromium browsers (Chrome/Edge/Brave) and Safari — there is nothing to add to
`/etc/hosts`. Caddy reads `SITE_HOST` from `.env` and serves that domain (see `Caddyfile`).

**HTTPS with zero config:** Caddy generates its own local certificate authority and issues a cert
for `SITE_HOST`. Because Caddy itself terminates TLS and serves PHP, WordPress sees the request as
HTTPS natively — no redirect loops.

> ⚠️ **`WORDPRESS_TABLE_PREFIX`**: leave this at the default `wp_`. Only change it if you are
> importing an existing WordPress database whose tables use a different prefix — and then it must
> match that database's prefix **exactly** (including any trailing underscore, e.g. `wp_mysite_`).
> A mismatch makes wp-cli report *"the site you have requested is not installed"*.

### Caveats

- **Browser support for `.localhost`:** Chromium browsers and Safari resolve `*.localhost`
  natively. Current Firefox does too; very old Firefox builds may need `network.dns.localDomains`.
- **Ports 80/443 must be free:** if you previously ran a host-level Nginx/Apache for local sites,
  stop it first — e.g. `sudo systemctl disable --now nginx`.
- **Trust the cert (optional):** the site works immediately, but the browser shows a one-time
  warning for Caddy's local CA. To remove it, run once:
  `docker compose exec caddy caddy trust` (asks for sudo to write the system trust store).
- **A different TLD** (e.g. `mysite.test`) works too, but then you *do* need an `/etc/hosts` entry
  pointing it at `127.0.0.1`. `.localhost` is the zero-config option.

---

## 🛠 Helper scripts

All scripts live in `scripts/` and are run **from the project root**.

| Script | Purpose |
| --- | --- |
| `./scripts/import-db.sh [file.sql]` | Import a SQL dump into the `db` container (defaults to `db.sql`). If the target DB already has tables, prompts to drop & recreate it first (default **No** keeps it and imports on top). |
| `./scripts/update-db-domains.sh <old> [new]` | Rewrite the site domain everywhere WordPress reads it: the live DB (wp-cli, with raw-SQL fallback), `wp-config.php` constants (`WP_HOME`/`WP_SITEURL`/`DOMAIN_CURRENT_SITE`), plus a report of any hard-coded hits in `wp-content/`. `new` defaults to `SITE_HOST`. |
| `./scripts/scan-wp-files.sh [dir]` | Report files/folders not part of a standard WordPress install — filesystem heuristics + optional `wp core verify-checksums`. Report only; defaults to `./wordpress`. |
| `./scripts/recreate-containers.sh` | Cleanly stop & remove this project's containers (`docker compose down --remove-orphans`) and recreate them (`up -d`). On-disk data in `./db` and `./wordpress` is preserved. |

> ℹ️ `scan-wp-files.sh` may report `wp-config-sample.php` failing checksum verification (with a
> *"doesn't verify against checksums"* error). This is **expected** — the official WordPress Docker
> image ships a slightly modified sample file. Only mismatches under `wp-admin/`/`wp-includes/` or
> unexpected extra files are worth investigating.

---

## ⛁ Database

A fresh `docker compose up -d` gives you an empty WordPress install ready for the web installer at
`https://<SITE_HOST>`. To restore an existing site instead:

**Import a dump** (defaults to `db.sql` in this directory):

```bash
./scripts/import-db.sh                 # imports ./db.sql
./scripts/import-db.sh local_dump.sql  # or a specific file
```

If the target database already contains tables, the script reports how many and asks whether to
drop and recreate it before importing. The prompt defaults to **No** (press Enter to keep the
existing DB and import on top). Answer **`y`** to start from a clean slate — useful because a dump
only recreates the tables it defines, so importing on top can leave behind stale tables the new
dump doesn't touch.

**Rewrite the domain** of an imported backup to your local one. Prefer doing it *after* import with
`update-db-domains.sh`, which uses wp-cli and safely rewrites serialized data:

```bash
./scripts/update-db-domains.sh myoldwebsite.com   # new domain defaults to SITE_HOST
./scripts/update-db-domains.sh myoldwebsite.com mysite.localhost
```

Alternatively, rewrite the `.sql` *before* importing (does not handle serialized data):

```bash
sed -i 's/https?:\/\/\(www\.\)myoldwebsite.com/<yourlocalurl>/g' local_dump.sql
sed -i 's/\(www\.\)myoldwebsite.com/<yourlocaldomain>/g' local_dump.sql
```

PS: For multisite, `DOMAIN_CURRENT_SITE` is updated automatically by `update-db-domains.sh`
(along with `WP_HOME`/`WP_SITEURL` if defined) — no manual edit needed.

---

## Common commands

```bash
docker compose up -d          # start
docker compose down           # stop (DB and WP files persist on disk)
docker compose logs -f caddy  # tail a service
docker compose exec caddy caddy trust   # trust the local HTTPS cert (one-time, optional)
docker compose exec db mysql -uroot -p${MYSQL_ROOT_PASSWORD} ${MYSQL_DATABASE}   # DB shell
```
