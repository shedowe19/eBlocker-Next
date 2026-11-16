#!/bin/sh
# Rebuild the pinned Tor source package; never install or start Tor here.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
output_dir=${OUTPUT_DIR:?Set OUTPUT_DIR to an absolute artifact directory}
case "$output_dir" in
    /*) ;;
    *) echo 'OUTPUT_DIR must be absolute.' >&2; exit 2 ;;
esac
if [ "$(dpkg --print-architecture)" != amd64 ]; then
    echo 'This workflow currently builds Tor for amd64 only.' >&2
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
        tor) have_tor=true ;;
        tor-geoipdb) have_geoip=true ;;
        tor-dbgsym) ;;
        *) echo "Unexpected Tor output package: $name" >&2; exit 1 ;;
    esac
    dpkg-deb --info "$package"
    cp -- "$package" "$output_dir/"
done
if [ "$have_tor" != true ] || [ "$have_geoip" != true ]; then
    echo 'Tor build did not produce both required Debian packages.' >&2
    exit 1
fi
