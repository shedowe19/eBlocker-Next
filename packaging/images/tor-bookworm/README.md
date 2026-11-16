# Tor 0.4.9.16 for eBlockerOS 4.0.3 and 4.1.0

The eBlockerOS 4.0.3 VM is based on Debian 12 Bookworm and ships Tor 0.4.7.16.
That client fails with missing `Desc=3 Microdesc=3` protocols
([issue #460][issue]). An isolated eBlockerOS 4.1.0 VM also uses Bookworm and
shipped Tor 0.4.9.11, which bootstrapped successfully before this update. This
recipe rebuilds Tor 0.4.9.16 from the official Debian source archive on Bookworm
for both eBlockerOS releases. The Raspberry Pi 4/5 image is 64-bit; the
intended package architectures are `amd64` (VM/PC) and `arm64` (Pi). No binary
packages or source archives are committed here.

## Build

Use a clean Debian 12 Bookworm build environment of the target architecture.
Install the build dependencies, then run the script from this directory:

```sh
apt-get install --no-install-recommends \
  build-essential fakeroot dpkg-dev debhelper quilt libssl-dev zlib1g-dev \
  libevent-dev asciidoc docbook-xml docbook-xsl xmlto dh-apparmor \
  libsystemd-dev pkg-config libcap-dev dh-autoreconf \
  liblzma-dev libzstd-dev dh-runit curl ca-certificates
if [ "$(dpkg --print-architecture)" = amd64 ]; then
  apt-get install --no-install-recommends libseccomp-dev
fi
DEBFULLNAME='Your Name' DEBEMAIL='you@example.org' \
  ./build.sh /path/to/new-empty-build-directory
```

The script downloads three pinned inputs over HTTPS, checks their SHA256
digests, and creates `tor` and `tor-geoipdb` packages. All inputs come from
[Debian's official Tor source pool](https://deb.debian.org/debian/pool/main/t/tor/).
The upstream tarball and Debian diff retain their original pinned hashes.
The `.dsc` is the Debian maintainer-signed copy: its checked SHA256 is
`0bc6b65b2ae7770bed55bdce9081f08cc90ca3fc099540f053ff446edcd1fb72`.
This replaces the unavailable Tor package-repository `.dsc`, without changing
the source version or either source payload. The default
`~eblab12+1` suffix identifies a lab build; maintainers can set
`PACKAGE_VERSION` for an official package revision.

Lab builds use `DEB_BUILD_OPTIONS=nocheck`; upstream unit tests are not run.
Pass `DEB_BUILD_OPTIONS=''` to run them in a release build.

The repository's GitHub package workflow invokes `build/debian/tor.sh` and
enables upstream unit tests by default. That wrapper currently targets `amd64`,
requires both binary packages and copies the resulting `.deb` files into the
absolute `OUTPUT_DIR` artifact directory. It does not install or start Tor.

## Historical validation of 0.4.9.15 on 3 November 2026

The runtime checks below describe the earlier 0.4.9.15 lab packages. They do
not establish runtime validation of the current 0.4.9.16 recipe.

The `amd64` package was built in an isolated Debian 12 Bookworm environment.
Installation on an isolated official eBlockerOS 4.0.3 VM upgraded only `tor`
and `tor-geoipdb` from 0.4.7.16-1. `tor@eblocker.service` reached 100%
bootstrap; HTTPS through its Unix SOCKS socket returned HTTP 200 from
torstatus.greensec.de and `IsTor: true` from check.torproject.org. After a VM
reboot, the service again bootstrapped 100% and the HTTPS check returned 200.

The `arm64` package was built natively in an isolated Debian 12 Bookworm
environment on a Raspberry Pi 4 running eBlockerOS 4.0.3. Installation again
upgraded only `tor` and `tor-geoipdb` from 0.4.7.16-1. The eBlocker Tor instance
reached 100% bootstrap, and a DNS query through its Tor DNS port returned an A
record. After a Pi reboot, Tor again reached 100%; the DNS query succeeded,
HTTPS through its Unix SOCKS socket returned HTTP 200, and Tor Project's API
returned `IsTor: true`.

An isolated clone of an eBlockerOS 4.1.0 VM (Debian 12 Bookworm, `amd64`) was
then tested with the same `amd64` lab package pair. Its existing Tor 0.4.9.11
already reached 100% bootstrap. An apt simulation and installation upgraded
only `tor` and `tor-geoipdb` to 0.4.9.15. After restarting `tor@eblocker`, it
reached 100% bootstrap; HTTPS through its Unix SOCKS socket returned HTTP 200
and Tor Project's API reported `IsTor: true`. The package versions, 100%
bootstrap, HTTPS 200 and `IsTor: true` were confirmed again after a VM reboot.
Neither running 4.1.0 VM received a package change; a snapshot of one was used
to create the isolated clone. An eBlockerOS 4.1.0 Raspberry Pi runtime was not
available for this test; the `arm64` build was tested on the
Bookworm-based 4.0.3 Pi as described above.

A routed eBlocker device test, upstream unit tests and maintainer review remain
release checks. This package does not change eBlocker itself or the security
support status of its Debian base.

[issue]: https://github.com/eblocker/eblocker/issues/460
