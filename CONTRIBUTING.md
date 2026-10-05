# Contributing

Start with [development](docs/DEVELOPMENT.md), [API policy](docs/API.md), and
[compatibility](docs/COMPATIBILITY.md). Use Mojo 1.1.0 and the native dependencies
in [DEPENDENCIES.md](docs/DEPENDENCIES.md).

Run `scripts/format`, then `scripts/check`. Changes to transfer/worker ownership
also need relevant failure fixtures and ASan. Keep `scripts/check-tsan` strict;
record runtime prerequisite failures rather than suppressing them. Compile every
changed example. Integration tests need an existing authorized test bucket and
random isolated prefixes; never create/delete arbitrary buckets. Ordinary checks
must work without paid cloud credentials.

Keep patches focused on concrete protocol requirements or adoption problems.
Preserve provider-neutral `ObjectStore` semantics and isolate S3-specific
capabilities. Add a regression test for a behavior bug, update API/compatibility
docs when behavior changes, and record actual evidence instead of inferring
support from successful compilation. Public API changes require changelog and
migration notes under the version policy.

For bug and compatibility reports, include:

- SDK commit/version, Mojo version, OS/architecture and native-library versions.
- Backend name/version, endpoint/addressing mode and TLS/CA configuration.
- Minimal synthetic-credential reproduction, expected/actual behavior and relevant test results.
- HTTP status/S3 code/request ID when safe, with credential values, Authorization,
  tokens, presigned URLs, object contents and private endpoint names redacted.

Never attach raw environment dumps or unredacted wire traces. For security
reports, follow [security guidance](docs/SECURITY.md) instead of posting exploit
details publicly. Generated signing fixtures use synthetic inputs; document the
oracle/version/seed when regenerating them. The repository license is MIT; do
not copy third-party implementation or fixture material without compatible
licensing and provenance.
