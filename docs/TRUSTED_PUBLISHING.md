# Current distribution route — October 5, 2026

The qualified first route for Mojo-S3 is a **deterministic GitHub source release**
plus the existing installed-source-prefix build helper. This pass only builds and
installs source artifacts; no publication, release, tag or account setting changes.

Current official [Mojo packaging guidance](https://mojolang.org/docs/tools/packaging/)
now describes rattler-build conda recipes, compiler-pinned `.mojoc` packages,
prefix.dev/anaconda.org/other conda-compatible indexes and the
[Modular community channel](https://github.com/modular/modular-community).
That is a real supported distribution mechanism, not an invented Mojo registry.
Community inclusion requires a reviewed recipe in the external community repo;
its maintained build/upload workflow handles channel publishing. No external
recipe/PR is created here. Mojo-S3's curl/OpenSSL/XML linker discovery, ABI/compiler
pin and independent installation must be qualified inside that conda route before
claiming registry-ready support. The current doc template uses older compiler
numbers; it is not a verified recipe for this SDK's Mojo 1.1.0 baseline.

[mojo precompile](https://mojolang.org/docs/cli/precompile/) produces a compiler-
version-bound artifact and explicitly says it is not a general distributable
format. The conda recipe pins the compiler around it; this SDK's source archive
avoids exporting an unqualified binary ABI. Community packaging is optional
future work, not a reason to broaden this release pass.

## Publishing authentication and provenance

[Current rattler-build authentication/upload source docs](https://github.com/prefix-dev/rattler-build/blob/main/docs/authentication_and_upload.md)
explicitly support **prefix.dev trusted publishing through GitHub Actions OIDC**.
The owner must create/select the channel and register the exact repository and
workflow under its Trusted Publishers settings; the workflow needs id-token:write.
No API token is required for that configured route. This is registry upload
authentication, distinct from optional Sigstore/GitHub provenance attestations.
The public rendered publishing page and CLI options also describe token/auth-store
fallbacks; their omissions do not mean OIDC is unsupported. The community upload
workflow currently has id-token:write and uses rattler-build upload prefix.

This SDK has not configured a channel/publisher, built a qualified conda recipe
or tested that exchange. No account settings, secrets, OIDC permissions or registry
workflow are added. GitHub source releases use repository publication permissions;
optional artifact attestations use OIDC separately. The qualified first source
route does not require registry trusted publishing. MojoShelf is a separate
community option, not the current official packaging route or an activated target.

## Existing source dry run

scripts/package normalizes ordering, ownership/modes/timestamps and gzip mtime;
it emits inner SHA256SUMS, revision/compiler/platform BUILDINFO and outer checksum.
These are provenance facts, not signed attestations. No compiled toolchain/runtime
is included. scripts/check-release installs outside the checkout (including a
prefix with spaces) and compiles the public root-facade consumer. The manual
release workflow is dry-run only, invokes native CI and has contents:read.
No publishing step, registry token or id-token permission is introduced.

## Small future owner checklist

1. Complete explicitly authorized live AWS qualification; review the exact head,
   API freeze, hosted CI and deterministic source/installation evidence.
2. Choose the version/tag and GitHub source-release route, review the prepared
   notes/checksums, and authorize publication as a separate action. Configure
   repository/tag/environment protections according to the owner's policy.
3. Only if conda distribution is desired later: qualify a commit/compiler-pinned
   recipe and native linking, select a user-owned channel or seek community
   inclusion, and configure the selected prefix.dev channel's exact repository/workflow
   Trusted Publisher if using its documented OIDC route. A token fallback requires
   protected account credentials; no token is needed for an accepted OIDC publisher. No account changes are required
   merely to review the current source artifact.
