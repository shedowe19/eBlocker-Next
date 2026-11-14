# eBlocker-Next: experimental monorepo refactoring

This is an independent integration of current official eBlocker sources, not an
upstream release and not yet production-ready. Installed-appliance and end-to-end validation
remain open; browser unit tests now pass in CI; see `docs/INTEGRATION.md`. No former user fork
or implementation is included.

## Layout

- `apps/core`: UI, REST/ICAP backend, certificate validator and base configuration.
- `services`: CoreDNS, dynamic DNS, network helpers and LED daemon.
- `libs`: crypto, registration API and asynchronous Redis library.
- `third_party`: eBlocker's Netty ICAP, RestExpress and Squid forks, plus DateAdapterJ source.
- `packaging`: bootstrap and image/Tor build tooling.
- `data`: filter-list and app definitions.
- `tools/environment-simulator`: safe development counterpart to privileged helpers.
- `legacy/dns`: older DNS implementation, retained explicitly rather than silently dropped.

All included component source is present in this checkout, not scattered across submodules. Standard
third-party package dependencies still come from their language registries.
`upstream.lock.json` records original URLs, branches, exact commits and notices.
The core is based on `feature/debian_bookworm`; companions use their documented
default branches. This does not imply every component is Bookworm-compatible.

## Safe development checks

```
python3 scripts/verify_workspace.py
mvn -B validate
mvn -B test
(cd services/coredns && go test ./...)
(cd services/dyndns && go test ./...)
(cd tools/environment-simulator && go test ./...)
```

Requirements: Maven 3.9.x, Java 11 for the upstream baseline, Go as specified by
each module (simulator requires 1.25), Node selected by the UI Maven plugin.
Native network helpers require libnet, libpcap and hiredis development libraries.
A Maven `validate` pass is NOT a successful compile, test, package or runtime test.

Do not run packaging installation scripts on a personal or production computer:
they can change networking, services, accounts and firewall state. Build and test
in an isolated disposable Debian Bookworm environment first.

## License and attribution

Original license files and copyright notices are retained within each component.
Most eBlocker components carry EUPL-1.2; the bundled forks retain their own
licenses (including Squid's GPLv2+). This is not a blanket relicensing. The upstream
UI package metadata says `UNLICENSED` while the repository carries EUPL notices;
resolve this metadata ambiguity before publishing a distributable release.
Do not imply endorsement by the eBlocker project. See `docs/INTEGRATION.md`.
