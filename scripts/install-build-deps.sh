#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$SCRIPT_DIR/configure-openeuler-repo.sh"

dnf -y --setopt=max_parallel_downloads=10 makecache
dnf install -y --setopt=install_weak_deps=False \
    --setopt=max_parallel_downloads=10 \
    binutils \
    ca-certificates \
    curl \
    diffutils \
    findutils \
    gcc \
    gcc-c++ \
    glibc-devel \
    hostname \
    libatomic \
    libstdc++-devel \
    make \
    ncurses-devel \
    patch \
    perl \
    perl-Digest-SHA \
    perl-File-Temp \
    perl-File-Which \
    perl-IPC-Cmd \
    perl-Time-Local \
    tar \
    xz

dnf clean all
rm -rf /var/cache/dnf
