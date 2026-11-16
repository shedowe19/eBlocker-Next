#!/bin/sh
# Build the imported, already-patched Squid tree without installing its packages.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
output_dir=${OUTPUT_DIR:?Set OUTPUT_DIR to an absolute artifact directory}
case "$output_dir" in
    /*) ;;
    *) echo 'OUTPUT_DIR must be absolute.' >&2; exit 2 ;;
esac

. /etc/os-release
if [ "${ID:-}" != debian ] || [ "${VERSION_CODENAME:-}" != bookworm ]; then
    echo 'Build Squid in the isolated Debian Bookworm build container.' >&2
    exit 2
fi
target_arch=${TARGET_ARCH:-amd64}
case "$target_arch" in
    amd64|arm64) ;;
    *) echo "Unsupported TARGET_ARCH: $target_arch" >&2; exit 2 ;;
esac
case "$(uname -m)" in
    x86_64) kernel_arch=amd64 ;;
    aarch64|arm64) kernel_arch=arm64 ;;
    *) echo 'Squid requires a native amd64 or arm64 Linux runner.' >&2; exit 2 ;;
esac
debian_arch=$(dpkg --print-architecture)
if [ "$debian_arch" != "$target_arch" ] || [ "$kernel_arch" != "$target_arch" ]; then
    echo "Squid architecture mismatch: target=$target_arch dpkg=$debian_arch kernel=$kernel_arch" >&2
    exit 2
fi

build_dir=$(mktemp -d "${TMPDIR:-/tmp}/eblocker-squid.XXXXXX")
trap 'rm -rf -- "$build_dir"' EXIT HUP INT TERM
mkdir -p "$build_dir/squid" "$output_dir"
cp -a "$root/third_party/squid/." "$build_dir/squid/"

(
    cd "$build_dir/squid"
    # The imported source already includes its Debian patches. The --target
    # entry point sets the dpkg build environment and checks Build-Depends, but
    # does not try applying that quilt series a second time.
    dpkg-buildpackage --target=binary -us -uc -j"${JOBS:-2}"
)

have_squid=false
have_common=false
for package in "$build_dir"/*.deb; do
    [ -f "$package" ] || continue
    name=$(dpkg-deb --field "$package" Package)
    case "$name" in
        eblocker-squid) have_squid=true; expected_arch=$target_arch ;;
        eblocker-squid-common) have_common=true; expected_arch=all ;;
        eblocker-squid-dbgsym) expected_arch=$target_arch ;;
        *) echo "Unexpected Squid output package: $name" >&2; exit 1 ;;
    esac
    package_arch=$(dpkg-deb --field "$package" Architecture)
    if [ "$package_arch" != "$expected_arch" ]; then
        echo "Wrong architecture for $name: expected $expected_arch, got $package_arch" >&2
        exit 1
    fi
    dpkg-deb --info "$package"
    cp -- "$package" "$output_dir/"
done
if [ "$have_squid" != true ] || [ "$have_common" != true ]; then
    echo 'Squid build did not produce both required Debian packages.' >&2
    exit 1
fi
