# Debian package builds

The **Debian packages** GitHub Actions workflow builds Debian 12 Bookworm
packages for **amd64**. Run it from the repository's Actions tab using
**Run workflow**. Changes to the workflow, package definitions and build helpers
also trigger it on `main`.

Five independent jobs build the existing package families in disposable
`debian:bookworm` containers:

| Group | Required packages |
|---|---|
| Java | eblocker-icapserver, eblocker-baseconfig, eblocker-certificate-validator, eblocker-ui, eblocker-bootstrap, eblocker-lists |
| Services | eblocker-coredns, eblocker-dyndns, eblocker-network-tools |
| Ruby | eblocker-led, eblocker-dns (legacy) |
| Squid | eblocker-squid, eblocker-squid-common |
| Tor | tor, tor-geoipdb |

The final **Complete package set** job requires all 15 packages. It inspects
each archive's package name, version, architecture and payload without installing
it or running its maintainer scripts. Debug-symbol packages may be included too.
The machine-readable inventory is `build/debian/packages.json`; the structural
tests check that no in-repository Debian package definition is omitted.

Download **debian-bookworm-amd64-complete** from the completed run for all
packages, `manifest.json` and `SHA256SUMS`. The manifest records the source commit
and each package's version, architecture, size and SHA256. Individual group
archives and build logs are also retained for 30 days.

## Build boundaries

- The Java reactor uses the local backend and libraries, including the filter-list
  module. Tests and UI production minification remain enabled. The existing
  `amd64-bookworm` bootstrap profile selects its repository configuration.
- The lists package uses the checked-in source data. Building it does not update
  external protection feeds or enable the optional `update-lists` profile.
- Native and Go packages use Bookworm libraries and Go 1.25. Ruby packaging vendors
  its path dependencies inside each package instead of relying on monorepo paths
  existing on the installed system.
- Squid's imported source already contains Debian patches. Its binary build entry
  point avoids applying them twice; Debian packaging symlinks are restored.
- Tor rebuilds the pinned 0.4.9.16 sources from the official Debian archive with
  SHA256 verification and upstream tests enabled.

These are package-build artifacts. Installation, upgrade and appliance integration
tests are separate gates; the workflow does not publish an APT repository or
install packages on a user's device.
