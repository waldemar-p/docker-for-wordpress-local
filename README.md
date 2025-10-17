
# Step: Configure Local Nginx Reverse Proxy for WordPress Docker Setup

The string `<yourlocalurl>` and `<yourlocaldomain>` are placeholder for your real local url and domain (with and without protocol).

To access your WordPress Docker container through a clean domain (like `http://<yourlocalurl>`) instead of `http://localhost:8080`, configure your **local Nginx** as a reverse proxy.

First execute `cp .env.example .env` and fill out the credentials.
Afterwards run the `fill-wp-config-creds.sh` to magically fill the credentials into your `wp-config.php`.

---

## 🧩 1. Add Host Entry

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

If you are using a backup from a different domain I recommend to duplicate the .sql and replace all instances of the old url with the local one.

```bash
sed -i 's/https?:\/\/\(www\.\)myoldwebsite.com/<yourlocalurl>/g' local_dump.sql
sed -i 's/\(www\.\)myoldwebsite.com/<yourlocaldomain>/g' local_dump.sql
```

Afterwards you can easily import the sql as root user and start coding! 🚀

PS: If already set, don't forget to change DOMAIN_CURRENT_SITE to your `<yourlocaldomain>`
