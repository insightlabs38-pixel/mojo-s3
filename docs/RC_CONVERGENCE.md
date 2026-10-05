# Final convergence — October 5, 2026

Work is isolated on `sdk/rc-prep` from the preserved `sdk/s3-phase2` checkpoint
`1e93cb313ca5ba43c3f141af6277347ec968967e` (hosted CI 37267071702 passed).
Version stays **0.1.0-dev**. Research, dependency builds and issue drafts stay
outside SDK history; nothing is submitted, published, tagged or merged into main.
The final report records the exact pushed head and its completed hosted CI result.

## Small SDK delta and API freeze

Experimental `list_object_versions`, `ObjectVersion`, `DeleteMarker`,
`VersionsPage` and `VersionsPaginator` are exported from the root facade.
Pages own all results; delete markers remain distinct from object versions.
Keys/prefixes use S3 URL decoding when the backend declares `url` encoding;
opaque version IDs are never decoded, ordered or interpreted, including `null`.
A relevant SDK bug was corrected: encoded listing '+' becomes a space, while '%2B' remains a literal plus, matching botocore. The shared fix also corrects ListObjectsV2.
The page bound is 1–1000 entries including delimiter prefixes, sizes are checked
Int64, and pagination validates advancing markers and detects cycles. Default
page budget is 10,000, configurable through 1,000,000; fixed-size SHA256 marker
fingerprints bound retained history. A failed page leaves paginator state intact.
No bucket versioning administration or automatic deletion is added.

The API freeze review is in [API_FREEZE.md](API_FREEZE.md). Transfer controls,
progress observers, multipart planning/inspection/copy, tagging, workload
providers, AssumeRole and version listing remain experimental. Core 0.1 source
contracts remain intended stable; no binary ABI or new platform promise is made.

CRC64NVME is evaluated and deferred in [CRC64NVME_DESIGN.md](CRC64NVME_DESIGN.md).
Resume and multipart checksum composition remain deferred. No further feature
phase is recommended before live AWS qualification.

## Current backend evidence

Latest stable identities were fetched at execution time, not assumed from old
reports. [COMPATIBILITY.md](COMPATIBILITY.md) distinguishes the historical cases.

| Backend | Current result and limit |
|---|---|
| MinIO RELEASE.2025-10-15T17-29-55Z, source `9e49d5e7a648f00e26f2246f4dc28e6b07f8c84a` | Existing native transfer/copy/tag/range contracts and new version listing pass on the tested keys. Multipart prefix/MaxUploads/order/marker and Unicode-tag deviations still reproduce independently. Encoded space/plus keys match boto3 after correcting the SDK listing decoder; this is not a backend defect. |
| Versity 1.8.0, release build `fd04bc1df2656298577b82667a4195c77f8c7563` | Encoded multipart tags, Unicode, invalid/duplicate rejection, COPY/REPLACE/empty tags, If-Match rejection, part copy/content and versioned tags pass. The old 1.0.16 tag/If-Match failures are historical. Current paired multipart markers return HTTP 400; version continuation repeats the marker version. Independent boto3/raw responses reproduce both; strict native pagination fails. |
| ZEROS3 `f391b7e552f654f59ec23e3f46fadf3f60c1d97d` | Existing baseline remains supported. Preserved UploadPartCopy HTTP 200/empty-body evidence remains a separate extension deviation; no parser relaxation or external repository fix. |

MinIO's latest archive download returned HTTP 410, so qualification used the
exact release-tag source built with Go 1.27.0; binary/source identity is recorded.
The hosted CI pin remains RELEASE.2025-04-22T22-12-26Z, not a floating latest:
the new release does not pass the full strict extension contract. Current-release
qualification is separate from that pinned hosted baseline. Versity version tests
use an explicitly configured local POSIX versioning store. None is live AWS proof.

## OpenSSL and bounded TSan closure

The original hash-table warning remains an instrumentation-boundary diagnostic:
the preserved fully instrumented hash controls remove it. No suppression is used.
The separate allocator flag race reproduces in Clang-instrumented OpenSSL 4.0.3
(`af1775b60dfa141a4ad762585052cabeb9f37e9e`) and development head
`4d25710dbfeacbb36d055592a3bc6811172248b1` with an independent C barrier/EVP-context
caller: 19/20 cold eight-thread processes in each; 0/20 single-thread and 0/20 warm
in each. Cold 32-thread stress reports 18/20 development, 20/20 stable. Diagnostics
identify the flag accesses in crypto/mem.c; no custom allocator/provider or SDK
imports are involved. This is a longstanding independent dependency bug candidate,
not evidence of SDK corruption or a newly discovered security vulnerability.

History includes the 1999 introduction, the acknowledged incomplete 2009 change,
the 2018 cache-line optimization, and #16970/#16980. Although GitHub labels #16980
closed/unmerged, its provider fixes were pushed individually to master; they did
not change this allocator flag. Issue-quality history/reproducer/draft are kept
outside SDK history. An atomic flag alone does not establish allocator-function
publication/customization semantics; no unverified external patch is proposed.

The known-good isolated nightly closure still detects a genuine Mojo race and
passes concurrent failure/joins and download cancellation controls. A 50 ms sleep
in the fault fixture was replaced with a bounded two-request rendezvous after it
failed to prove overlap; normal/ASan/TSan pass with the deterministic fixture.
Strict check-tsan is unchanged. New version paths receive normal/ASan/isolated
TSan tests. This qualifies neither released Mojo TSan nor all dependencies.

## Release decision

The ordinary gate, new faults, examples, independent public consumer/install,
current local backend classification, API review and deterministic source dry-run
are the technical gates. Exact-head hosted CI is recorded in the final handoff.
No known SDK data-corruption defect was identified in this focused pass; this is
not a formal audit. See [RELEASE_READINESS.md](RELEASE_READINESS.md) for blockers.

Live AWS remains unavailable and is a final-release blocker; distribution
activation also requires a later owner decision. A deterministic GitHub source
release is the practical first route. Current Mojo documentation also describes
rattler-build/conda and the Modular community channel, but this SDK's native-link
integration has not been qualified through that route. No registry flow is
invented or activated. [TRUSTED_PUBLISHING.md](TRUSTED_PUBLISHING.md) records the
current mechanisms and the small future owner checklist.
