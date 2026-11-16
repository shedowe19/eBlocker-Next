#!/usr/bin/env bash
# Run only in the disposable Bookworm CI container.
set -euo pipefail
source /etc/os-release
[[ ${ID:-} == debian && ${VERSION_CODENAME:-} == bookworm ]]
target_arch=${TARGET_ARCH:-amd64}
case "$target_arch" in
  amd64) native_machine=x86_64 ;;
  arm64) native_machine=aarch64 ;;
  *) echo "Unsupported target architecture: $target_arch" >&2; exit 2 ;;
esac
[[ $(dpkg --print-architecture) == "$target_arch" ]]
[[ $(uname -m) == "$native_machine" ]]
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  build-essential dpkg-dev fakeroot debhelper pkg-config python3 \
  file xz-utils zstd unzip ca-certificates curl git
case "${1:?Specify java, services, ruby, squid or tor}" in
  java)
    apt-get install -y --no-install-recommends maven chromium fonts-liberation optipng \
      zlib1g-dev libpng-dev autoconf automake libtool
    cat > /usr/local/bin/eblocker-ci-chromium <<'CHROME'
#!/bin/sh
exec /usr/bin/chromium --no-sandbox --disable-dev-shm-usage "$@"
CHROME
    chmod 755 /usr/local/bin/eblocker-ci-chromium
    ;;
  services)
    apt-get install -y --no-install-recommends libnet1-dev libpcap-dev libhiredis-dev
    ;;
  ruby)
    apt-get install -y --no-install-recommends ruby ruby-dev bundler rake libffi-dev
    ;;
  squid)
    apt-get install -y --no-install-recommends \
      ed libltdl-dev pkgconf dh-apparmor libcppunit-dev libcap2-dev libcrypt-dev \
      libecap3-dev libexpat1-dev libgnutls28-dev libkrb5-dev comerr-dev libldap2-dev \
      libnetfilter-conntrack-dev libpam0g-dev libsasl2-dev libsystemd-dev libtdb-dev \
      libxml2-dev nettle-dev libssl-dev
    ;;
  tor)
    apt-get install -y --no-install-recommends \
      quilt libssl-dev zlib1g-dev libevent-dev asciidoc docbook-xml docbook-xsl \
      xmlto dh-apparmor libsystemd-dev libcap-dev dh-autoreconf liblzma-dev \
      libzstd-dev dh-runit
    # The pinned Tor DSC conflicts with libseccomp-dev on non-x86 targets.
    if [[ "$target_arch" == amd64 ]]; then
      apt-get install -y --no-install-recommends libseccomp-dev
    fi
    ;;
  *) echo 'Unknown build group' >&2; exit 2 ;;
esac
