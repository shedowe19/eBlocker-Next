#!/usr/bin/env bash
# Build the existing native/Go Debian packages without installing them.
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
: "${OUTPUT_DIR:?Set OUTPUT_DIR to an absolute artifact directory}"
[[ "$OUTPUT_DIR" = /* ]] || { echo 'OUTPUT_DIR must be absolute' >&2; exit 2; }
. /etc/os-release
[[ "${VERSION_CODENAME:-}" = bookworm ]] || { echo 'Debian Bookworm is required' >&2; exit 2; }
export TARGET_ARCH=${TARGET_ARCH:-amd64}
case "$TARGET_ARCH" in
    amd64) machine=x86_64 ;;
    arm64) machine=aarch64 ;;
    *) echo "Unsupported target architecture: $TARGET_ARCH" >&2; exit 2 ;;
esac
[[ "$(dpkg --print-architecture)" = "$TARGET_ARCH" &&
   "$(uname -s)" = Linux && "$(uname -m)" = "$machine" ]] || {
    echo "A native Bookworm/$TARGET_ARCH build environment is required" >&2; exit 2;
}
case " ${DEB_BUILD_OPTIONS:-} ${DEB_BUILD_PROFILES:-} " in
    *' nocheck '*) echo 'Refusing to disable package tests' >&2; exit 2 ;;
esac
for command in go dpkg-buildpackage dpkg-deb make cc getent groupadd; do
    command -v "$command" >/dev/null || { echo "Missing build command: $command" >&2; exit 2; }
done
[[ "$(go env GOHOSTOS)" = linux && "$(go env GOHOSTARCH)" = "$TARGET_ARCH" ]] || {
    echo "A native Linux/$TARGET_ARCH Go toolchain is required" >&2; exit 2;
}
export GOOS=linux GOARCH="$TARGET_ARCH"

# Debian packages record their source commit in the build manifest. Avoid
# embedding checkout state, which is also unavailable when the container user
# differs from the checkout owner. This applies to builds and package tests.
export GOFLAGS="${GOFLAGS:+$GOFLAGS }-buildvcs=false"

# The upstream packaging gives its setuid helper to this named group.
# Package preinst creates the group on the target; only the build container is
# prepared here. No package or maintainer script is installed/executed.
if ! getent group icapd >/dev/null; then
    groupadd --system icapd
fi
mkdir -p -- "$OUTPUT_DIR"

for component in coredns dyndns network-tools; do
    package="eblocker-$component"
    directory="$root/services/$component"
    (
        cd -- "$directory"
        ARCH="$TARGET_ARCH" dpkg-buildpackage --build=binary --no-sign
    )
    found=0
    while IFS= read -r -d '' artifact; do
        name=$(dpkg-deb -f "$artifact" Package)
        architecture=$(dpkg-deb -f "$artifact" Architecture)
        [[ "$architecture" = "$TARGET_ARCH" ]] || {
            echo "Unexpected architecture in $artifact: $architecture" >&2; exit 1;
        }
        if [[ "$name" = "$package" ]]; then
            found=1
        elif [[ "$name" != "$package-dbgsym" ]]; then
            echo "Unexpected package in $artifact: $name" >&2; exit 1
        fi
        dpkg-deb --info "$artifact"
        install -m 0644 -- "$artifact" "$OUTPUT_DIR/"
    done < <(find "$root/services" -maxdepth 1 -type f \
        \( -name "${package}_*.deb" -o -name "${package}-dbgsym_*.deb" \) -print0)
    [[ "$found" = 1 ]] || { echo "No binary package produced for $package" >&2; exit 1; }
done
