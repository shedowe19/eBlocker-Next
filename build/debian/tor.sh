#!/bin/sh
# Rebuild the pinned Tor source package; never install or start Tor here.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
output_dir=${OUTPUT_DIR:?Set OUTPUT_DIR to an absolute artifact directory}
case "$output_dir" in
    /*) ;;
    *) echo 'OUTPUT_DIR must be absolute.' >&2; exit 2 ;;
esac
target_arch=${TARGET_ARCH:-amd64}
case "$target_arch" in
    amd64|arm64) ;;
    *) echo "Unsupported TARGET_ARCH: $target_arch" >&2; exit 2 ;;
esac
case "$(uname -m)" in
    x86_64) kernel_arch=amd64 ;;
    aarch64|arm64) kernel_arch=arm64 ;;
    *) echo 'Tor requires a native amd64 or arm64 Linux runner.' >&2; exit 2 ;;
esac
debian_arch=$(dpkg --print-architecture)
if [ "$debian_arch" != "$target_arch" ] || [ "$kernel_arch" != "$target_arch" ]; then
    echo "Tor architecture mismatch: target=$target_arch dpkg=$debian_arch kernel=$kernel_arch" >&2
    exit 2
fi

build_dir=$(mktemp -d "${TMPDIR:-/tmp}/eblocker-tor.XXXXXX")
trap 'rm -rf -- "$build_dir"' EXIT HUP INT TERM
mkdir -p "$output_dir"
# Unlike the historical lab recipe, CI enables the upstream tests by default.
export DEB_BUILD_OPTIONS=${DEB_BUILD_OPTIONS-}
sh "$root/packaging/images/tor-bookworm/build.sh" "$build_dir"

have_tor=false
have_geoip=false
for package in "$build_dir"/*.deb; do
    [ -f "$package" ] || continue
    name=$(dpkg-deb --field "$package" Package)
    case "$name" in
        tor) have_tor=true; expected_arch=$target_arch ;;
        tor-geoipdb) have_geoip=true; expected_arch=all ;;
        tor-dbgsym) expected_arch=$target_arch ;;
        *) echo "Unexpected Tor output package: $name" >&2; exit 1 ;;
    esac
    package_arch=$(dpkg-deb --field "$package" Architecture)
    if [ "$package_arch" != "$expected_arch" ]; then
        echo "Wrong architecture for $name: expected $expected_arch, got $package_arch" >&2
        exit 1
    fi
    dpkg-deb --info "$package"
    cp -- "$package" "$output_dir/"
done
if [ "$have_tor" != true ] || [ "$have_geoip" != true ]; then
    echo 'Tor build did not produce both required Debian packages.' >&2
    exit 1
fi
