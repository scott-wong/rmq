#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$SCRIPT_DIR/configure-openeuler-repo.sh"

dnf -y --setopt=max_parallel_downloads=10 makecache
dnf -y --setopt=max_parallel_downloads=10 upgrade --security
dnf install -y --setopt=install_weak_deps=False \
    --setopt=max_parallel_downloads=10 \
    ca-certificates \
    findutils \
    hostname \
    libatomic \
    ncurses-libs \
    shadow \
    tar \
    tzdata \
    util-linux \
    util-linux-user

dnf clean all
rm -rf /var/cache/dnf

if command -v gcc >/dev/null 2>&1 || command -v make >/dev/null 2>&1; then
    printf 'ERROR: final image contains compiler or build tools\n' >&2
    exit 1
fi
