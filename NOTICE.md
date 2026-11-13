# eBlocker-Next source notices

This is an independent experimental integration, not an official eBlocker release
and not endorsed by its upstream authors. Sources were freshly imported on
2026-11-13 from the exact commits recorded in `upstream.lock.json`.

Each component retains its original license, copyright and NOTICE files. There is
no blanket relicensing of the repository. Consult the per-component license paths
in the manifest, including EUPL, Apache, MIT and GPL-licensed components.

Local modifications include component relocation, local dependency wiring, build
entry points, dependency reproducibility, test isolation, resource lifecycle
cleanup and removal of embedded deployment/authentication material. Detailed
changes and validation limits are recorded in Git history and
`docs/INTEGRATION.md`. Original public provenance is retained there and in the
manifest; unsafe upstream credential-bearing history is deliberately not imported.

Package-level license metadata discrepancies are called out in the integration
document rather than silently overwritten. All runtime and packaging components
must be reviewed and validated before a distributable appliance release.
