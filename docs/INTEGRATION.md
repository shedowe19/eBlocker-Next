# Integration and refactoring status

## Current verified result

Verified remote baseline: commit `938d9c8e6a430b3960aa4a1bb696be00ecb73ccb`,
[GitHub Actions run 43564934584](https://github.com/shedowe19/eBlocker-Next/actions/runs/43564934584),
completed successfully on 2026-11-14. All seven jobs passed: structure, build-tools,
CoreDNS, DynDNS, environment simulator, native compilation and the Maven reactor.
The Java job reports 2837 tests, zero failures/errors and five integration skips.
The same job ran ChromeHeadless 157: **280 UI tests passed**. This is browser unit
coverage, not an end-to-end installed appliance test.


22 pinned official component sources are present in one checkout, without Git
submodules. 16 Maven modules share one reactor; Java parents/dependencies and
Ruby Git-source dependencies resolve to local component paths. Provenance and
original notices remain in `upstream.lock.json` and each component.

- Four structural/provenance tests pass; documented entry points work from a
  different working directory.
- Maven reactor through certificate-validator: BUILD SUCCESS. 2837 Java tests,
  zero failures/errors, five remaining integration skips. This includes 2074 backend tests
  and 58 certificate-validator tests.
- Bootstrap Maven lifecycle succeeds; upstream defines no tests for that module.
- CoreDNS: four Go packages pass. DynDNS redisdyndns and environment-simulator
  internal tests pass.
- All four native tools compile/link against locally extracted official Debian
  Bookworm packages with verified SHA256. They were not run or installed.
- UI: npm ci succeeds using the unchanged lockfile; development bundle builds all
  six modules. All 18 generated local JS/CSS references exist.
- 91 Ruby files pass syntax compilation; two pure DNS utility tests pass.

These are not installed-appliance or end-to-end browser tests. Do not treat this as a
production-ready release.

## Repairs and refactoring performed

- Root Makefile provides safe build/test commands, never service installation.
- Native Makefile honors CC/CPPFLAGS/CFLAGS/LDFLAGS/LDLIBS and phony targets.
- Obsolete DateAdapterJ SNAPSHOT dependency is replaced with locally compiled
  tagged source, distinct version 1.1.5-eblocker.1 and Java11. License/NOTICE are
  retained; upstream signing/publication plugins are not used.
- Netty socket tests bind loopback; alias-allocation tests no longer depend on
  physical NIC names. No network configuration is changed by those tests.
- Certificate tests use ephemeral CA, valid/expired/revoked/untrusted leaves and a
  signed CRL on loopback. Real PKIX/revocation checks stay enabled and CRL fetching
  is asserted. Production TLS policy is unchanged.
- CertificateValidatorApp exposes bounded worker cleanup; tests close its pools,
  streams and HTTP fixture. The server entry point also cleans up workers on
  startup failure. Configuration streams close on success and parse failure;
  four new tests cover default/override semantics and error cleanup.
- Fresh UI tests generate locale references/template caches before Karma.
- UI parallel template generation propagates failures instead of reporting success;
  completion is single-shot. Every nonzero Karma exit status is an error. Dedicated
  dependency-free Node regression tests cover success/error/empty task cases.
- The six-module development bundle was rebuilt successfully after this refactor.
- UI Maven lifecycle uses npm ci rather than an unlocked install.

## Remaining blockers and limits

### Browser and appliance validation

The original local runner could not start ChromeHeadless without a sandbox/socket
restriction; no browser sandbox was disabled. That unit-test blocker is now
resolved by the verified GitHub Actions run above. All 280 browser assertions
passed there. Browser-based end-to-end verification of an installed Bookworm
appliance remains open. The current development host is Debian13, not Bookworm;
no result on this host establishes Bookworm runtime compatibility.

No disposable Bookworm VM, installed services, hardware LED/SPI, packet capture,
proxy/filtering/DNS integration, reboot, upgrade or rollback has been exercised.
Image tooling retains upstream old package/distribution assumptions. Its scripts
must not run on personal/production computers. Squid's Debian build remains unrun.

### Legacy Ruby DNS

Legacy DNS is retained for reference, not included in the supported/default build:
its Gemfile requires async-dns~1.0.2, the current official fork is1.3.0.1, which
requires async-io~1.15 while the pinned eBlocker async-io fork is1.0.0. Its resolver
passes a positional options hash to a keyword API, incompatible with Ruby3, and
its gemspec constrains Bundler~1.7. Widening versions alone is not a safe repair.
Only two address-sorting tests exist for this path. Prefer tested CoreDNS; a
legacy revival needs separately characterized async/protocol contracts.

### Dependencies and licensing

The UI still uses upstream AngularJS1.8/Node16-era dependencies. The source
integration has not upgraded frameworks or claimed dependency security approval.
Registry403 from npm was resolved by fetching the same official tarballs with
curl, validating every tarball against the committed lockfile integrity, and
priming the local cache; no integrity/TLS relaxation or alternate registry used.

UI package metadata says UNLICENSED and LED gemspec says Proprietary while their
repositories carry license notices. Resolve metadata contradictions before a
distributable release; no blanket relicensing was applied.

## Credential hygiene and publication

Upstream Maven settings contained seven embedded GitHub-token-shaped values,
including XML-escaped spelling. Their validity was not tested. They now use
GITHUB_TOKEN environment references. Additional embedded provider credentials
were removed from filter-list configuration; provider access now requires external
SQUIDBLACKLIST_USERNAME/SQUIDBLACKLIST_PASSWORD or explicitly supplied properties,
and fails before network access if missing. Two focused provider tests pass. An embedded deployment private key was
excluded; VM provisioning requires an external license key, fails closed if
absent and installs it mode0600 without logging its contents.

A fresh sanitized Git history replaced the unsafe local import history. The latter
is outside this repository and must never be published. Known keys in upstream
unit-test fixtures are test data, never usable deployment credentials.
`scripts/check_credentials.py` checks all reachable Git blobs for known token
patterns; it is not a complete secret audit. Its latest run passed.

Publication target: `shedowe19/eBlocker-Next` (public), created by its owner.
This is an experimental source snapshot, not a supported appliance release.
The owner imported the source, and remote CI passed on the baseline identified above. Credentials, package caches,
logs and generated build output are excluded from this source repository.

## Test environment notes

Locally used Temurin JDK11, Maven3.9.9, Go1.25, Node16.13 and Debian Bookworm native
libraries/Ruby3.1. Restricted JVM self-attachment required the already-resolved
ByteBuddy test agent via Surefire `-DargLine=-javaagent:<local-agent-jar>`.
No tests were disabled for that fix; production JVM arguments are unchanged.
Keep proxy/truststore configuration outside the repo.

## Reactivated upstream tests

Three former skips were repaired without contacting external services. Netty's
null-body comparator violated symmetry; the implementation and six insertion-order
regressions now pass. Its unknown-input test now checks Netty4 empty-buffer
behavior. The parental metadata test uses a real temporary JSON file, deterministic
mtime and verifies duplicate notifications do not reload. Netty's full220 tests
and the six metadata-service tests pass with no skips.

Five skips remain explicit integration requirements: four registration tests need
a dedicated backend with a fresh database; Jedis expects a local Redis fixture.
They do not block source upload but their integration behavior is not verified.

## Publication hardening

Following a blocked upload preflight, bundled production keystore/Tor-control
secret values were removed, not encoded or hidden. Tor requires explicit external
auth provisioning and fails closed; backend keystore secrets must be supplied
locally. See `docs/SECRET-PROVISIONING.md`. This adds installation prerequisites;
no turnkey appliance claim is made. Unchanged rejected payloads were not retried.

The post-sanitization full Java reactor through certificate-validator passed:
2832 tests, zero failures/errors, five explicit integration skips. The two new Tor
authentication tests confirm invalid credentials never open a connection and
rejected authentication closes it. No live Tor service was contacted.

## Local follow-up after publication was blocked

Historical note: these changes were first tested locally while publication was
blocked. They are included in the owner-imported baseline verified above. No
blocked snapshot upload was retried through another route.
Four synthetic regression tests now cover token-family recognition, XML-escaped
values, provider/Tor assignments and permitted external references in the limited
credential detector. Combined with the four structure checks, all eight pass.
The disabled real-backend registration test no longer logs provisioned private-key
or certificate contents; it checks nonempty output files instead. Its backend
requirement remains explicit, and this edit does not claim license activation
has been validated.

Registrations GET/POST now close both Jersey responses and clients, including
transport, HTTP-error, decoding-error and response-cleanup-error paths. Five new
mocked lifecycle tests cover both verbs; the existing four HTTP/DNS MockServer
tests also pass. TLS, authentication headers and error mapping are unchanged.
The full Java reactor was rerun after these changes: BUILD SUCCESS, 2837 tests,
zero failures/errors and the same five explicitly skipped integration cases.
