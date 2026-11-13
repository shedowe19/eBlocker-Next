# Required local secret provisioning

This experimental source tree intentionally ships without reusable deployment
credentials. It is not a drop-in appliance image. Do not restore passwords or
private deployment keys from the historical upstream configuration.

## Backend keystores

Supply these keys in the external configuration read via `localConfiguration.path`:

- `ca.keystore.password`
- `icapserver.keystore.password`
- `registration.truststore.password`
- `parentalControl.redirect.keyStore.password`

There are deliberately no bundled bindings for these secrets. Provision fresh
private keystores and matching passwords locally. For public-certificate-only
truststores, import the certificates into an operator-managed truststore with a
locally chosen password. Never commit the configured values or private stores.

The certificate validator's external configuration must supply
`validator.pin.trustStore.password` before using a protected pin truststore.
Its blank bundled value does not bypass JKS integrity checks; a protected store
with a mismatched password will not load.

## Tor control

Both Tor templates require `/etc/tor/eblocker-control-auth.conf`, which must be
provisioned outside this repository. Use a loopback-only ControlPort and a Tor
HashedControlPassword derived locally from a unique installation password. Missing
configuration fails closed. Never expose an unauthenticated control listener.

The backend reads `EBLOCKER_TOR_CONTROL_PASSWORD`. Missing/blank/non-printable or
oversized credentials disable its control connection. Authentication uses Tor's
hex format to avoid control-protocol injection; rejected authentication closes
the connection. Do not log the password or share the environment file.

## Filter provider and image tooling

SquidBlacklist access uses externally supplied `SQUIDBLACKLIST_USERNAME` and
`SQUIDBLACKLIST_PASSWORD`, or explicitly supplied in-memory properties. Missing
credentials fail before any provider request. Provider access/license entitlement
must be arranged by the operator; no provider account was tested here.

VM provisioning requires an external `eblocker_license_key_path`. The private key
is not included and is installed mode0600 without logging its contents.

No provisioning, password rotation, Tor startup, network configuration or service
installation was performed on any user computer during this refactoring.
