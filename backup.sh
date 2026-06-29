#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ ! -f .env ]]; then
  echo "Missing .env file. Copy .env.example and set KOPIA_PASSWORD." >&2
  exit 1
fi

# shellcheck disable=SC2046
export $(grep -v '^#' .env | xargs)

if [[ -z "${KOPIA_PASSWORD:-}" ]]; then
  echo "KOPIA_PASSWORD is not set in .env" >&2
  exit 1
fi

COMPOSE=(docker compose --profile backup)
KOPIA=( "${COMPOSE[@]}" run --rm -T kopia )

# in place backups are created
BACKUP_PATHS=(
  /backup/wordpress
  /backup/db
  /backup/caddy_data
  /backup/caddy_config
)

kopia() {
  "${KOPIA[@]}" "$@"
}

repo_connected() {
  kopia repository status >/dev/null 2>&1
}

init_repo() {
  echo "Creating Kopia repository at /data/repo..."
  kopia repository create filesystem --path=/data/repo

  echo "Setting retention and compression policies..."
  kopia policy set --global \
    --compression=zstd \
    --keep-latest=7 \
    --keep-daily=14 \
    --keep-weekly=8 \
    --keep-monthly=12

  for path in "${BACKUP_PATHS[@]}"; do
    kopia policy set "$path" --compression=zstd
  done
}

run_backup() {
  echo "Creating snapshots..."
  kopia snapshot create "${BACKUP_PATHS[@]}"

  echo "Running maintenance..."
  kopia maintenance run --full

  echo "Backup finished at $(date -Is)"
}

if ! repo_connected; then
  init_repo
fi

run_backup
