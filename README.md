# wordpress_template
This project sets up a **WordPress** web-instance using Docker Compose with three main services, plus an optional **Kopia** backup service:

---

## 📦 Services Overview

### 1. **WordPress**
- **Image**: `wordpress:latest`
- **Port**: Exposed via Caddy
- **Volumes**: Persists WordPress content in the `wordpress` volume
- **Environment**:
  - Reads database credentials from `.env`
- **Networks**:
  - `frontend`: connects to Caddy
  - `backend`: connects to MySQL

### 2. **Caddy (Web Server & Reverse Proxy)**
- **Image**: `caddy:2.10`
- **Port Mapping**: `443 → 8081` on host (access via `https://wp.local:8081`)
- **TLS**: Uses `tls internal` or Let's Encrypt depending on configuration
- **Config**: 
  - Loaded from a generated `Caddyfile` in the `conf/` directory
- **Features**:
  - Automatic HTTPS (for real domains) or internal TLS for development
  - Gzip compression
- **Volumes**:
  - Persists TLS and configuration data via `caddy_data` and `caddy_config`
- **Security**:
  - Runs as read-only
  - Uses `tmpfs` for temporary and cert-related directories
  - Requires `NET_ADMIN` capability (needed for Caddy’s network config)

### 3. **MySQL (Database)**
- **Image**: `mysql:5.7`
- **Volumes**: Data persisted in `db_data`
- **Environment**:
  - Fully controlled via `.env` (e.g., DB name, user, root password)
- **Networks**:
  - `backend`: communicates only with WordPress

### 4. **Kopia (Backups)**
- **Image**: `kopia/kopia:latest`
- **Profile**: `backup` — not started by `./run.sh`; runs on demand via `backup.sh` or cron
- **Mode**: CLI-only (no web UI, no exposed port)
- **Repository**: Encrypted filesystem repo stored in the `kopia_data` volume (`/data/repo`)
- **Snapshots** (read-only mounts):
  - `wordpress` → `/backup/wordpress`
  - `db_data` → `/backup/db`
  - `caddy_data` → `/backup/caddy_data`
  - `caddy_config` → `/backup/caddy_config`
- **Persistence**: Config, cache, and logs in `kopia_config`, `kopia_cache`, and `kopia_logs`

---

## ⚙️ Configuration

### `.env` File

Before running the stack, create a `.env` file in the root directory with:

```env
HOSTNAME=wp.local
EMAIL=hostmaster@fenker.eu

DB_NAME=wordpress
DB_USER=wordpress
DB_PASSWORD=your_db_password
DB_ROOT_PASSWORD=your_root_password

# Encryption password for the Kopia backup repository
KOPIA_PASSWORD=your_kopia_password
```

### Run the Stack

To start the services, run:

```bash
./run.sh
```

The caddyfile needs to be rendered with the .env variables, which is done in the `run.sh` script.

---

## 💾 Backups with Kopia

Backups use Kopia in **CLI-only** mode: there is no long-running Kopia container and no web interface. The `backup.sh` script spins up a temporary Kopia container, creates snapshots, runs maintenance, and exits.

On the **first run**, `backup.sh` also creates the repository and sets default policies (zstd compression; retention: 7 latest, 14 daily, 8 weekly, 12 monthly). Later runs only snapshot and maintain.

### Run a backup manually

From the project root:

```bash
./backup.sh
```

### Schedule daily backups (cron)

Add a crontab entry on the host (adjust time and path as needed):

```cron
0 2 * * * /path/to/wordpress_template/backup.sh >> /var/log/kopia-backup.log 2>&1
```

Edit with `crontab -e`.

### Kopia CLI via Docker Compose

All commands below use the `backup` profile and run Kopia in a one-off container. Run them from the project root.

**Repository status** (connected repo, storage usage):

```bash
docker compose --profile backup run --rm -T kopia repository status
```

**List snapshots**:

```bash
docker compose --profile backup run --rm -T kopia snapshot list
```

**Show a specific snapshot** (paths, sizes, IDs):

```bash
docker compose --profile backup run --rm -T kopia snapshot list --all
```

**View retention/compression policy** (global or per path):

```bash
docker compose --profile backup run --rm -T kopia policy get --global
docker compose --profile backup run --rm -T kopia policy get /backup/wordpress
```

**Restore a snapshot** (replace `<snapshot-id>` with an ID from `snapshot list`):

```bash
mkdir -p ./restore
docker compose --profile backup run --rm -T \
  -v "$(pwd)/restore:/restore" \
  kopia snapshot restore <snapshot-id> /restore
```

**Run maintenance manually** (garbage collection, compaction):

```bash
docker compose --profile backup run --rm -T kopia maintenance run --full
```

**View recent Kopia CLI logs** (stored in the `kopia_logs` volume):

```bash
docker compose --profile backup run --rm --entrypoint sh kopia \
  -c 'ls -lt /app/logs/cli-logs | head; tail -20 /app/logs/cli-logs/*.log'
```

### MySQL backup note

The database is backed up as a raw copy of the MySQL data directory. If MySQL is running during the snapshot, the backup may be inconsistent. For production, consider stopping the database briefly during backup or adding a `mysqldump` step before the Kopia snapshot.

---

## A Quick Guide on WordPress

User Login URL: `https://<hostname>/wp-login.php`
