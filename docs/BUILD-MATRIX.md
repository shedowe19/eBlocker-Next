# Build and integration matrix

This repository is a source integration baseline. A component's unit-test success
is not evidence that an appliance release or migration is safe.

| Component group | Local entry point | External requirements | Validation boundary |
|---|---|---|---|
| Java backend/libs | root `mvn test` | JDK11, Maven3.9, Maven registries | Unit tests, not an installed backend |
| AngularJS UI | `apps/core/eblocker-ui`: `npm ci`, `npm test` | Node16.13 baseline, npm registry, ChromeHeadless | 280 ChromeHeadless browser-unit tests pass in CI; installed UI E2E pending |
| CoreDNS | `services/coredns`: `go test ./...` | Go modules | Four test packages pass |
| DynDNS | `services/dyndns`: `go test ./...` | Go modules | redisdyndns passes |
| Simulator | `tools/environment-simulator`: `go test ./...` | Go1.25 | Internal tests pass |
| Native network tools | `services/network-tools`: `make` | C compiler, libpcap/libnet/hiredis headers | All four compile/link in Ubuntu24.04 CI; earlier Bookworm-library compile only |
| Legacy Ruby DNS | `legacy/dns`: Bundler/gemspec | Ruby/Bundler and native gem libraries | 91 syntax checks, two utilities pass; incompatible dependency bundle |
| Squid fork | `third_party/squid`: upstream Debian build | Debian build dependencies | Not built; packaging audit required |
| VM/bootstrap | `packaging` | Disposable privileged Debian VM | Not executed; must not use on production |

## Runtime dependency boundaries to preserve

- The backend talks to proxy/ICAP, DNS, Redis and privileged system helpers.
  Refactoring must characterize those protocols before replacing components.
- Moving source does not move installed paths under `/opt/eblocker-icap`, service
  definitions or package relationships. Keep them stable until migration tests exist.
- Filter/app data have their own generation/update lifecycle; do not treat imported
  lists as a verified up-to-date protection feed.
- Image tooling still contains old distribution/package assumptions. A source
  checkout alone does not produce a tested Bookworm image.
- VM provisioning now requires an externally supplied license private key. It
  must not be committed, copied from test fixtures or printed in logs.

## Release gates

1. Complete package builds without consuming unpublished local artifacts.
2. UI unit-test/build gate passed in run43564934584 (280 tests); installed-app E2E remains open.
3. Exercise an isolated Bookworm VM, with no production network or user credentials.
4. Verify filtering, TLS, IPv4/IPv6, DNS/Redis failover, update/reboot and rollback.
5. Review license metadata and test fixtures; run credential checks on the exact
   publication commit. Specify target GitHub repository and visibility before push.

Latest verified baseline: commit `938d9c8e6a430b3960aa4a1bb696be00ecb73ccb`,
[all seven CI jobs green](https://github.com/shedowe19/eBlocker-Next/actions/runs/43564934584)
on 2026-11-14. This workflow executes tests and compilation, not Debian package
builds, image provisioning, service installation or upgrade/rollback validation.
