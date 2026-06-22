
# Local Docker Setup

## ⚡ TL;DR — quick start

```bash
cp .env.example .env          # then edit credentials, PROJECT_NAME, LOCAL_URLS
docker compose up -d          # boot; WordPress core auto-populates ./wordpress
./fill-wp-config-creds.sh     # write .env creds into wordpress/wp-config.php

# Optional — restore an existing site from a dump:
./import-db.sh db.sql              # import ./db.sql (set WORDPRESS_TABLE_PREFIX to match it first!)
./update-db-domains.sh old.com     # rewrite domain → first LOCAL_URLS entry

# Optional — reach it via a clean domain instead of localhost:8080:
./setup-local-domain.sh            # /etc/hosts + host-Nginx proxy for LOCAL_URLS (uses sudo)
```

Site is now at `http://localhost:8080` (or `http://<LOCAL_URLS>` after the last step).

---

The string `<yourlocalurl>` and `<yourlocaldomain>` are placeholder for your real local url and domain (with and without protocol).

To access your WordPress Docker container through a clean domain (like `http://<yourlocalurl>`) instead of `http://localhost:8080`, configure your **local Nginx** as a reverse proxy.

First execute `cp .env.example .env` and fill out the credentials. Set `LOCAL_URLS` to your local
domain(s) — space-separated if you want more than one (e.g. `LOCAL_URLS="mysite.local www.mysite.local"`).
Afterwards run the `fill-wp-config-creds.sh` to magically fill the credentials into your `wp-config.php`.

> ⚠️ **`WORDPRESS_TABLE_PREFIX`**: leave this at the default `wp_`. Only change it if you are
> importing an existing WordPress database whose tables use a different prefix — and then it must
> match that database's prefix **exactly** (including any trailing underscore, e.g. `wp_mysite_`).
> A mismatch makes wp-cli report *"the site you have requested is not installed"*.

---

## 🛠 Helper scripts

| Script | Purpose |
| --- | --- |
| `fill-wp-config-creds.sh` | Inject `.env` DB credentials and table prefix into `wordpress/wp-config.php`. |
| `import-db.sh [file.sql]` | Import a SQL dump into the `db` container (defaults to `db.sql`). |
| `setup-local-domain.sh [url...]` | Add `/etc/hosts` entries + a host-Nginx reverse proxy for the URL(s), then test & reload Nginx. Defaults to `LOCAL_URLS`. |
| `update-db-domains.sh <old> [new]` | Rewrite the site domain inside the live DB (wp-cli, with raw-SQL fallback). `new` defaults to the first `LOCAL_URLS` entry. |
| `scan-wp-files.sh [dir]` | Report files/folders not part of a standard WordPress install — filesystem heuristics + optional `wp core verify-checksums`. Report only; defaults to `./wordpress`. |

Steps 1–4 below describe what these scripts automate.

---

## 🧩 1. Add Host Entry

> ⚡ Steps 1 and 2 are automated by `./setup-local-domain.sh <yourlocalurl>` (or just
> `./setup-local-domain.sh` to use `LOCAL_URLS` from `.env`). The manual steps below explain what it does.

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
./import-db.sh                 # imports ./db.sql
./import-db.sh local_dump.sql  # or a specific file
```

**Rewrite the domain** of an imported backup to your local one. Prefer doing it *after* import with
`update-db-domains.sh`, which uses wp-cli and safely rewrites serialized data:

```bash
./update-db-domains.sh myoldwebsite.com   # new domain defaults to first LOCAL_URLS entry
./update-db-domains.sh myoldwebsite.com mysite.local
```

Alternatively, rewrite the `.sql` *before* importing (does not handle serialized data):

```bash
sed -i 's/https?:\/\/\(www\.\)myoldwebsite.com/<yourlocalurl>/g' local_dump.sql
sed -i 's/\(www\.\)myoldwebsite.com/<yourlocaldomain>/g' local_dump.sql
```

Afterwards you can easily import the sql as root user and start coding! 🚀

PS: If already set, don't forget to change DOMAIN_CURRENT_SITE to your `<yourlocaldomain>`
