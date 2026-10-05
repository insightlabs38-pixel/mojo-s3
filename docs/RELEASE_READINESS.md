# Release-readiness checkpoint — October 4, 2026

**0.1.0-dev remains development software.** Phase-2 adds useful native S3 data-plane
APIs and experimental workload credentials/transfers; semantics and stability are
in [PHASE2.md](PHASE2.md), scope in RELEASE_SCOPE.md.

| Check | Evidence and limit |
|---|---|
| Hosted baseline | [run 37248323851](https://github.com/insightlabs38-pixel/mojo-s3/actions/runs/37248323851) passed at `44faa2a`; ordinary/install/MinIO/ZEROS3/ASan |
| Hosted phase-2 | [Branch runs](https://github.com/insightlabs38-pixel/mojo-s3/actions?query=branch%3Asdk%2Fs3-phase2); inspect the completed result for the exact pushed commit |
| Adjacent compiler | Full ordinary checks and examples passed with exact nightly 1.2.0.dev2026100406; this does not establish released TSan support |
| Ordinary phase-2 | Mojo 1.1.0: precompile, units, deterministic protocol cases, credential fixtures, copy/batch faults, download cleanup/cancellation/write faults, TLS and examples |
| Installation | Source archive installs into an independent prefix with spaces; compiled downstream consumer passes; occupied installation refused |
| MinIO | Copy/conditions/batch/HeadBucket, version-aware reads/copy/delete, four negotiated checksums buffered+streamed, ranged1/2/4/8 odd-tail/small/empty, controlled multipart cancellation/progress passed |
| ZEROS3 | Common/file/multipart/manager and new copy/conditions/batch/ranged/control contracts passed |
| Versity | Common/file/multipart/manager/ranged/control passed; wrong If-Match accepted, so new conditional contract FAILED; copy/batch sequence not qualified by that halted test |
| ASan | Download faults/ranges1/2/4/8/controlled multipart/manager tested separately in the local phase-2 qualification |
| Isolated nightly TSan | Original candidate closure passed real race prerequisite/unchanged strict/live/STS/TLS/stress; later strict run reports an intermittent OpenSSL-internal cold-start warning; individual new paths are separate evidence |
| AWS | Compiled opt-in harness/refusal checks only; no credentials/live execution |
| Performance | Three local wall-time/RSS samples per streamed/ranged1/2/4/8, multipart1/2/4/8 and checksum operation; loopback/cache/compiler-load limits in BENCHMARKS.md |
| Platforms | Linux x86-64 only; no ARM64/macOS execution or compiled ABI promise |

Runtime logs/patches live outside this SDK repository in dedicated contribution
bundles. Original snapshots remain immutable; passing historical runs do not erase
the later OpenSSL warning. Strict check-tsan is byte-identical to baseline.

## Source distribution

Deterministic source archives include normalized entries, SHA256SUMS, BUILDINFO
with revision/content hash/compiler/platform and outer checksum. Release dry run
builds twice byte-for-byte, derives notes from CHANGELOG, and installs the artifact
into an independent consumer. Manual Actions workflow reuses native CI before
artifact upload; contents:read only. No publishing step, secret, release/tag or
account-side configuration. [Owner setup](TRUSTED_PUBLISHING.md).

## Remaining before 0.1.0

Review the public API and phase-2 hosted CI; execute explicitly authorized live AWS
against an existing dedicated unversioned bucket; qualify the actual distribution
route; decide supported platform/compiler claims from execution. Refresh/cancellation/
ranged downloads remain experimental, multipart composite checksums/resume and
AssumeRole remain deferred. Investigate the unsuppressed OpenSSL TSan warning and
obtain a supported released Modular runtime closure before claiming TSan support.
Versity conditional behavior remains a documented backend limitation. No current
critical data-corruption defect has been identified by these scoped tests; this
is not an exhaustive security/race audit.
