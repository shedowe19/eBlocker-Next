#!/usr/bin/env bash
# Package complete Ruby bundles using the existing Debian metadata.
# Builds happen in temporary copies; dpkg extraction never runs maintainer scripts.
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
for command in ruby bundle rake dpkg-buildpackage dpkg-deb make; do
    command -v "$command" >/dev/null || { echo "Missing build command: $command" >&2; exit 2; }
done
mkdir -p -- "$OUTPUT_DIR"

if [[ "$#" = 0 ]]; then
    failed=0
    for component in services/led legacy/dns; do
        slug=${component//\//-}
        # Use a fresh shell so errexit remains active inside each build, even
        # while collecting both independent results and their complete logs.
        if bash "${BASH_SOURCE[0]}" --component "$component" 2>&1 | tee "$OUTPUT_DIR/$slug-build.log"; then
            echo "$component: built and bundle smoke check passed"
        else
            echo "$component: FAILED; see $slug-build.log" >&2
            failed=1
        fi
    done
    exit "$failed"
fi
[[ "$#" = 2 && "$1" = --component ]] || { echo 'Unsupported arguments' >&2; exit 2; }
component=$2
case "$component" in
    services/led) package=eblocker-led; smoke=led ;;
    legacy/dns) package=eblocker-dns; smoke=dns ;;
    *) echo "Unsupported Ruby component: $component" >&2; exit 2 ;;
esac

scratch=$(mktemp -d "${TMPDIR:-/tmp}/eblocker-ruby.XXXXXXXX")
trap 'rm -rf -- "$scratch"' EXIT
stage="$scratch/source"
cp -a -- "$root/$component" "$stage"
cd -- "$stage"

# Copy every explicit monorepo path dependency into the package itself. Relative
# Gemfile paths remain valid after relocation to /opt and need no source checkout.
ROOT_SOURCE="$root/$component" ruby <<'RUBY'
require 'fileutils'
source = ENV.fetch('ROOT_SOURCE')
gemfile = File.read('Gemfile')
rewritten = gemfile.gsub(/:path\s*=>\s*'([^']+)'/) do
  relative = Regexp.last_match(1)
  original = File.expand_path(relative, source)
  raise "Missing source dependency: #{original}" unless File.directory?(original)
  destination = File.join('vendor', 'sources', File.basename(original))
  FileUtils.mkdir_p(File.dirname(destination))
  FileUtils.cp_r(original, destination)
  ":path => '#{destination}'"
end
File.write('Gemfile', rewritten)
RUBY

bundle config set --local path vendor/bundle
bundle config set --local cache_all true
bundle install --jobs "${JOBS:-2}" --retry 3
bundle cache --all
bundle check
# This invokes the original Makefile build/test/install sequence. Any existing
# rake tests run with the resolved bundle; failures abort the binary package.
bundle exec dpkg-buildpackage --build=binary --no-sign

found=0
while IFS= read -r -d '' artifact; do
    [[ "$(dpkg-deb -f "$artifact" Package)" = "$package" ]] || continue
    [[ "$(dpkg-deb -f "$artifact" Architecture)" = "$TARGET_ARCH" ]] || {
        echo "Unexpected package architecture: $artifact" >&2; exit 1;
    }
    extracted="$scratch/extracted"
    mkdir -p -- "$extracted"
    dpkg-deb --extract "$artifact" "$extracted"
    # Hide the build-time path before checking the extracted installation. A
    # bundle that accidentally retained absolute source paths must fail here.
    mv -- "$stage" "$scratch/build-source-not-installed"
    (
        cd -- "$extracted/opt/$package"
        export BUNDLE_GEMFILE="$PWD/Gemfile"
        bundle check
        if [[ "$smoke" = led ]]; then
            bundle exec ruby -Ilib -e 'require "eblocker/led/version"; require "eblocker/led/server"; require "process/daemon"; raise "missing LED server" unless Eblocker::Led::Server'
        else
            bundle exec ruby -Ilib -e 'require "eblocker/dns/version"; require "eblocker/dns/server"; require "eblocker/async/redis"; require "eblocker/async/redis/async-io"; require "eblocker/async/redis/pool"; require "process/daemon"; Cache.new(2); Eblocker::Dns::Server::Resolver.new([[:udp, "127.0.0.1", 15353]], {}, nil)'
        fi
    )
    dpkg-deb --info "$artifact"
    install -m 0644 -- "$artifact" "$OUTPUT_DIR/"
    install -m 0644 -- Gemfile.lock "$OUTPUT_DIR/$package-Gemfile.lock"
    found=1
done < <(find "$scratch" -maxdepth 1 -type f -name "${package}_*.deb" -print0)
[[ "$found" = 1 ]] || { echo "No verified binary package produced for $package" >&2; exit 1; }
