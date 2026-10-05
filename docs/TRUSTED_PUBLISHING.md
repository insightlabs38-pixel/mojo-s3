# Source distribution and future publishing

The qualified distribution route is a commit-pinned source archive and installed
source-prefix helper. No official Mojo registry schema is invented. MojoShelf's
current [specification](https://github.com/mojoshelf/mojoshelf/blob/main/specs/03_database_cli.md)
uses author publish tokens, not a documented OIDC trusted-publisher exchange.
Its Pixi/git source modes still require native curl/OpenSSL/XML linker integration
qualification. A registry publication is therefore deferred.

`scripts/package` sorts entries, normalizes ownership/modes/timestamps, uses
SOURCE_DATE_EPOCH (default commit time), and gzip mtime=0. It creates a versioned
source archive, internal SHA256SUMS, BUILDINFO.json with source revision/content
hash/compiler/platform, and an outer checksum. These are build provenance facts,
not signed attestations. Compiled packages, toolchains and native libraries are
excluded. `scripts/check-release` installs from that archive outside the checkout
and runs an independent consumer, including a prefix containing spaces.

`.github/workflows/release.yml` is manual **dry-run only** and first invokes the
shared native CI gates: format, ordinary tests, examples, independent installation,
MinIO, ZEROS3 and ASan. Then `scripts/release-dry-run` requires clean source,
checks version consistency/installation, builds twice and compares byte-for-byte,
and extracts release notes from CHANGELOG. The workflow uploads a temporary Actions
artifact, with contents:read; it cannot create tags/releases or publish packages.
AWS remains a separate explicitly authorized gate. Experimental TSan is documented
separately and is not released-Mojo support. No publishing secrets or OIDC write
permissions are requested for this unsigned source dry run.

## Owner steps after this run

1. Review phase-2 source and hosted CI, perform the authorized AWS qualification,
   and resolve release-critical gaps. Version remains 0.1.0-dev until then.
2. Select the reviewed commit, update VERSION/package.json/CHANGELOG together,
   and run the manual source-release-dry-run workflow on that branch.
3. Download and verify the source archive's outer/internal checksums and BUILDINFO;
   review generated notes and independent-install results.
4. For GitHub source releases, configure protected environments/required reviewers
   and tag permissions yourself, then approve a future separately reviewed
   publishing workflow. GitHub artifact attestations support OIDC if later added
   with id-token:write/attestations:write; this run has not configured or issued them.
5. For MojoShelf, first qualify its actual native-link integration and confirm its
   current account/token process. Register the tin/account yourself and store any
   required author token in an appropriate protected secret. Do not call this
   trusted publishing until the registry documents and accepts an OIDC exchange.

No package, release, tag, publishing token or external trusted-publisher account
configuration was created by this phase.
