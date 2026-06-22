
# Local Docker Setup

## ⚡ TL;DR — quick start

```bash
cp .env.example .env                 # then edit credentials, PROJECT_NAME, LOCAL_URLS
docker compose up -d                 # boot; WordPress core auto-populates ./wordpress
./scripts/fill-wp-config-creds.sh    # write .env creds into wordpress/wp-config.php

# Optional — restore an existing site from a dump:
./scripts/import-db.sh db.sql            # import ./db.sql (set WORDPRESS_TABLE_PREFIX to match it first!)
./scripts/update-db-domains.sh old.com   # rewrite domain → first LOCAL_URLS entry

# Optional — reach it via a clean domain instead of localhost:8080:
./scripts/setup-local-domain.sh          # /etc/hosts + host-Nginx http+https proxy for LOCAL_URLS (uses sudo)
```

> All helper scripts live in `scripts/` — run them **from the project root** (as shown above).

Site is now at `http://localhost:8080` (or `http://<LOCAL_URLS>` / `https://<LOCAL_URLS>` after the last step).

---

The string `<yourlocalurl>` and `<yourlocaldomain>` are placeholder for your real local url and domain (with and without protocol).

To access your WordPress Docker container through a clean domain (like `http://<yourlocalurl>`) instead of `http://localhost:8080`, configure your **local Nginx** as a reverse proxy.

First execute `cp .env.example .env` and fill out the credentials. Set `LOCAL_URLS` to your local
domain(s) — space-separated if you want more than one (e.g. `LOCAL_URLS="mysite.local www.mysite.local"`).
Afterwards run `./scripts/fill-wp-config-creds.sh` to magically fill the credentials into your `wp-config.php`.

> ⚠️ **`WORDPRESS_TABLE_PREFIX`**: leave this at the default `wp_`. Only change it if you are
> importing an existing WordPress database whose tables use a different prefix — and then it must
> match that database's prefix **exactly** (including any trailing underscore, e.g. `wp_mysite_`).
> A mismatch makes wp-cli report *"the site you have requested is not installed"*.

---

## 🛠 Helper scripts

All scripts live in `scripts/` and are run **from the project root**.

| Script | Purpose |
| --- | --- |
| `./scripts/fill-wp-config-creds.sh` | Inject `.env` DB credentials and table prefix into `wordpress/wp-config.php`. |
| `./scripts/import-db.sh [file.sql]` | Import a SQL dump into the `db` container (defaults to `db.sql`). If the target DB already has tables, prompts to drop & recreate it first (default **No** keeps it and imports on top). |
| `./scripts/setup-local-domain.sh [url...]` | Add `/etc/hosts` entries + a host-Nginx reverse proxy for the URL(s) serving **both http and https** (self-signed cert generated via Docker), then test & reload Nginx. Prompts before overwriting an existing config. Defaults to `LOCAL_URLS`. |
| `./scripts/update-db-domains.sh <old> [new]` | Rewrite the site domain everywhere WordPress reads it: the live DB (wp-cli, with raw-SQL fallback), `wp-config.php` constants (`WP_HOME`/`WP_SITEURL`/`DOMAIN_CURRENT_SITE`), plus a report of any hard-coded hits in `wp-content/`. `new` defaults to the first `LOCAL_URLS` entry. |
| `./scripts/scan-wp-files.sh [dir]` | Report files/folders not part of a standard WordPress install — filesystem heuristics + optional `wp core verify-checksums`. Report only; defaults to `./wordpress`. |

> ℹ️ `scan-wp-files.sh` may report `wp-config-sample.php` failing checksum verification (with a
> *"doesn't verify against checksums"* error). This is **expected** — the official WordPress Docker
> image ships a slightly modified sample file. Only mismatches under `wp-admin/`/`wp-includes/` or
> unexpected extra files are worth investigating.

Steps 1–4 below describe what these scripts automate.

---

## 🧩 1. Add Host Entry

> ⚡ Steps 1 and 2 are automated by `./scripts/setup-local-domain.sh <yourlocalurl>` (or just
> `./scripts/setup-local-domain.sh` to use `LOCAL_URLS` from `.env`). The manual steps below explain what it does.

Edit your `/etc/hosts` file:

```bash
sudo nano /etc/hosts
```

Add the following line (ensure there’s **no** IPv6 entry like `::1 <yourlocalurl>` — that can cause issues):

```
127.0.0.1   <yourlocalurl>
```

---

## ⚙️ 2. Add Nginx Site Configuration

Create a new configuration file, for example `/etc/nginx/sites-available/<yourlocalurl>.conf`:

```nginx
server {
    listen 80;
    server_name <yourlocalurl>;

    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Enable the configuration:

```bash
sudo ln -s /etc/nginx/sites-available/<yourlocalurl>.conf /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx
```

> 🔒 **HTTPS:** browsers auto-upgrade bare hostnames to `https://`. If your domain has no
> `listen 443 ssl` block of its own, the request falls through to whatever the host's *default*
> TLS server is — often yielding a **502**. `setup-local-domain.sh` therefore also emits a 443
> block backed by a self-signed cert it generates via Docker (`certs/<yourlocalurl>.pem`,
> installed to `/etc/nginx/certs/`). The cert is self-signed, so expect a one-time browser warning.

---

## 🚀 3. Verify Setup

Make sure your WordPress Docker containers are running:

```bash
docker compose up -d
```

Then visit:

👉 `http://<yourlocalurl>`

You should see your WordPress site without needing to include `:8080`.

---

✅ **Tip:** If you ever see the "Welcome to nginx" or "Apache2 Default Page," double-check:
- Your `/etc/hosts` entry (no `::1` line)
- That your proxy configuration points to the correct port (usually `8080`)
- That your local Nginx service is running and using the correct config

---

## ⛁ 4. Database

Either run your wordpress environment and set up a database or use your credentials to fill your database with a backup.

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
./scripts/update-db-domains.sh myoldwebsite.com   # new domain defaults to first LOCAL_URLS entry
./scripts/update-db-domains.sh myoldwebsite.com mysite.local
```

Alternatively, rewrite the `.sql` *before* importing (does not handle serialized data):

```bash
sed -i 's/https?:\/\/\(www\.\)myoldwebsite.com/<yourlocalurl>/g' local_dump.sql
sed -i 's/\(www\.\)myoldwebsite.com/<yourlocaldomain>/g' local_dump.sql
```

Afterwards you can easily import the sql as root user and start coding! 🚀

PS: For multisite, `DOMAIN_CURRENT_SITE` in `wp-config.php` is updated automatically by
`update-db-domains.sh` (along with `WP_HOME`/`WP_SITEURL` if defined) — no manual edit needed.
