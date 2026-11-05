#!/usr/bin/env bash
set -euo pipefail

release="openEuler-24.03-LTS-SP4"
arch="${ARCH:-$(uname -m)}"
case "$arch" in
    arm64) arch="aarch64" ;;
esac

gpg_key="${GPG_KEY:-/etc/pki/rpm-gpg/RPM-GPG-KEY-openEuler}"
repo_file="${REPO_FILE:-/etc/yum.repos.d/openEuler.repo}"
mirrors=(
    "${OPENEULER_MIRROR:-https://mirrors.xtom.de/openeuler}"
    "https://mirrors.huaweicloud.com/openeuler"
    "https://mirror.accum.se/mirror/openeuler.org"
    "https://repo.openeuler.org"
)

[ -r "$gpg_key" ] || {
    printf 'ERROR: missing openEuler GPG key: %s\n' "$gpg_key" >&2
    exit 1
}

selected=
for mirror in "${mirrors[@]}"; do
    mirror="${mirror%/}"
    case "$mirror" in
        https://*) ;;
        *)
            printf 'ERROR: openEuler mirror must use HTTPS: %s\n' "$mirror" >&2
            exit 1
            ;;
    esac

    probe="$mirror/$release/OS/$arch/repodata/repomd.xml"
    printf '[repo] probing %s\n' "$mirror"
    if curl --fail --silent --show-error --location \
        --connect-timeout 8 --max-time 20 \
        --output /dev/null "$probe"; then
        selected="$mirror"
        break
    fi
    printf '[repo] unavailable, trying next mirror\n' >&2
done

[ -n "$selected" ] || {
    printf 'ERROR: no usable openEuler RPM mirror found\n' >&2
    exit 1
}

repo_tmp="$(mktemp)"
trap 'rm -f "$repo_tmp"' EXIT

cat > "$repo_tmp" <<EOF
[OS]
name=OS
baseurl=$selected/$release/OS/$arch/
enabled=1
gpgcheck=1
gpgkey=file://$gpg_key
metadata_expire=1h
skip_if_unavailable=False

[everything]
name=everything
baseurl=$selected/$release/everything/$arch/
enabled=1
gpgcheck=1
gpgkey=file://$gpg_key
metadata_expire=1h
skip_if_unavailable=False

[EPOL]
name=EPOL
baseurl=$selected/$release/EPOL/main/$arch/
enabled=1
gpgcheck=1
gpgkey=file://$gpg_key
metadata_expire=1h
skip_if_unavailable=False

[update]
name=update
baseurl=$selected/$release/update/$arch/
enabled=1
gpgcheck=1
gpgkey=file://$gpg_key
metadata_expire=1h
skip_if_unavailable=False
EOF

install -m 0644 "$repo_tmp" "$repo_file"
printf '[repo] selected %s\n' "$selected"
