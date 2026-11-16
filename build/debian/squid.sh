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
if [ "$(dpkg --print-architecture)" != amd64 ]; then
    echo 'This workflow currently builds Squid for amd64 only.' >&2
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
        eblocker-squid) have_squid=true ;;
        eblocker-squid-common) have_common=true ;;
        eblocker-squid-dbgsym) ;;
        *) echo "Unexpected Squid output package: $name" >&2; exit 1 ;;
    esac
    dpkg-deb --info "$package"
    cp -- "$package" "$output_dir/"
done
if [ "$have_squid" != true ] || [ "$have_common" != true ]; then
    echo 'Squid build did not produce both required Debian packages.' >&2
    exit 1
fi
