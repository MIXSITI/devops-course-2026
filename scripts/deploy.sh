#!/usr/bin/env bash
# Доставка статического ресурса на devops-vm
# Использование: scripts/deploy.sh [--dry-run]
set -euo pipefail

REMOTE="devops"
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"

# cwRsync и его ssh вызываются парой: поток rsync через OpenSSH Windows повреждается.
if [[ -d "${HOME}/tools/cwrsync648/bin" ]]; then
    export PATH="${HOME}/tools/cwrsync648/bin:${PATH}"
fi

ROOT="$(git rev-parse --show-toplevel)"
SITE_DIR="${ROOT}/site"
cd "$ROOT"

dry_run=0
if [[ $# -gt 1 ]]; then
    echo "Слишком много аргументов" >&2
    exit 1
fi
if [[ $# -eq 1 ]]; then
    if [[ "$1" == "--dry-run" ]]; then
        dry_run=1
    else
        echo "Неизвестный аргумент: $1" >&2
        exit 1
    fi
fi

if [[ ! -f "${SITE_DIR}/index.html" ]]; then
    echo "Файл site/index.html отсутствует, доставка не выполняется" >&2
    exit 1
fi

if [[ -n "$(git -C "$ROOT" status --porcelain)" ]]; then
    echo "Есть незафиксированные изменения, доставка не выполняется" >&2
    exit 1
fi

rsync_args=(-avz --delete --chmod=D755,F644 -e "ssh -o BatchMode=yes -o ConnectTimeout=5")
if [[ "$dry_run" -eq 1 ]]; then
    rsync_args+=(--dry-run)
fi

rsync "${rsync_args[@]}" "site/" "${REMOTE}:${REMOTE_DIR}/"

if [[ "$dry_run" -eq 1 ]]; then
    exit 0
fi

if ! curl -fsS --cacert "$CA_CERT" --connect-timeout 5 -o /dev/null "$SITE_URL"; then
    echo "Проверка доступности ${SITE_URL} не пройдена" >&2
    exit 1
fi

git -C "$ROOT" rev-parse --short HEAD
