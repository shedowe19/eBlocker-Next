#!/usr/bin/env bash
# Build Debian archives only. Never install packages or run maintainer scripts.
set -Eeuo pipefail

root_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
target_arch=${TARGET_ARCH:-amd64}
case "$target_arch" in
    amd64) bootstrap_profile=amd64-bookworm ;;
    arm64) bootstrap_profile=raspios-bookworm ;;
    *) printf 'Unsupported TARGET_ARCH: %s\n' "$target_arch" >&2; exit 2 ;;
esac
: "${OUTPUT_DIR:?Set OUTPUT_DIR to an absolute package output directory}"
if [[ $OUTPUT_DIR != /* ]]; then
    printf 'OUTPUT_DIR must be absolute: %s\n' "$OUTPUT_DIR" >&2
    exit 1
fi

for tool in java mvn dpkg-deb; do
    command -v "$tool" >/dev/null || {
        printf 'Required build tool is missing: %s\n' "$tool" >&2
        exit 1
    }
done
java_version=$(java -XshowSettings:properties -version 2>&1 |
    sed -n 's/^[[:space:]]*java.specification.version = //p')
if [[ $java_version != 11 ]]; then
    printf 'The Java package build requires JDK 11; found %s\n' "$java_version" >&2
    exit 1
fi
if [[ ! -x ${CHROME_BIN:-} ]]; then
    printf 'Set CHROME_BIN to the executable CI Chromium launcher for UI tests.\n' >&2
    exit 1
fi

mkdir -p -- "$OUTPUT_DIR"
cd -- "$root_dir"
printf 'Building %s Maven packages with bootstrap profile %s\n' "$target_arch" "$bootstrap_profile"
# The UI activates quickrun on the presence of skipTests; do not set that property.
# No update-lists profile: package the checked-in data without fetching external feeds.
bash "$root_dir/build/debian/maven-ci.sh" \
    "-P$bootstrap_profile" "-DdebTargetDir=$OUTPUT_DIR" clean package

declare -A expected=(
    [eblocker-icapserver]=0
    [eblocker-baseconfig]=0
    [eblocker-certificate-validator]=0
    [eblocker-ui]=0
    [eblocker-bootstrap]=0
    [eblocker-lists]=0
)
while IFS= read -r -d '' archive; do
    package=$(dpkg-deb --field "$archive" Package)
    if [[ ! ${expected[$package]+present} ]]; then
        continue
    fi
    architecture=$(dpkg-deb --field "$archive" Architecture)
    version=$(dpkg-deb --field "$archive" Version)
    if [[ $architecture != all || -z $version || $version == *'[['* || $version == *'${'* ]]; then
        printf 'Invalid package metadata in %s: %s %s %s\n' \
            "$archive" "$package" "$version" "$architecture" >&2
        exit 1
    fi
    dpkg-deb --contents "$archive" >/dev/null
    expected[$package]=$((expected[$package] + 1))
    printf 'Verified %s (%s, %s): %s\n' "$package" "$version" "$architecture" "$archive"
done < <(find "$OUTPUT_DIR" -maxdepth 1 -type f -name '*.deb' -print0)

for package in "${!expected[@]}"; do
    if [[ ${expected[$package]} != 1 ]]; then
        printf 'Expected exactly one %s archive, found %s\n' \
            "$package" "${expected[$package]}" >&2
        exit 1
    fi
done
