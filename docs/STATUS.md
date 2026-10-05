# Current status — October 5, 2026

Version **0.1.0-dev** remains unreleased. Final preparation is on `sdk/rc-prep`,
from preserved convergence head `1e93cb313ca5ba43c3f141af6277347ec968967e` on
`sdk/s3-phase2`; that head passed hosted CI 37267071702. Main remains
`1c8afa72581e51c1437d6cfedbea4d0a814fb607`. The final evidence report records the
new exact head and completed CI result; [branch CI](https://github.com/insightlabs38-pixel/mojo-s3/actions?query=branch%3Asdk%2Frc-prep).
No merge, release, tag, registry publication or upstream submission occurred.

The completed architecture and 5 GiB wire evidence are in [CONVERGENCE.md](CONVERGENCE.md).
This final pass adds only experimental bounded object-version/delete-marker
listing, fixes a relevant encoded-listing identity bug and timing-dependent test rendezvous, reviews the API, classifies
current backend releases and reproduces the independent OpenSSL allocator race.
CRC64NVME is evaluated and deferred; automatic resume and broad new S3 surfaces
remain deferred. See [RC_CONVERGENCE.md](RC_CONVERGENCE.md) and [API_FREEZE.md](API_FREEZE.md).

Current Versity 1.8.0 passes the old encoded-tag and If-Match cases. Current
MinIO 2025-10-15 still deviates in multipart listing/Unicode tags. Versity also has
version-listing continuation limits detailed in [COMPATIBILITY.md](COMPATIBILITY.md).
ZEROS3 baseline support remains separate from its malformed UploadPartCopy
extension. No SDK workaround hides malformed backend success.

Mojo 1.1.0 / Linux x86-64 is the released baseline. The isolated exact nightly
1.2.0.dev2026100406 closure is an experiment, not supported production TSan.
The original uninstrumented OpenSSL hash-table warning disappears with visible
synchronization. The separate cold allocator-flag race reproduces on fully
instrumented OpenSSL stable 4.0.3 and current development head. Small C/SDK
controls, source/history and reports remain outside SDK history; no suppression.
No new tcmalloc investigation or LLVM reconstruction was performed in this pass.

Live AWS has not been executed. Source packaging/install is qualified separately
from registry activation. Current official Mojo conda/community packaging is
real but not yet qualified for this SDK's native linking. The practical first
route remains deterministic GitHub source releases after explicit authorization.
[Release blockers](RELEASE_READINESS.md), [distribution](TRUSTED_PUBLISHING.md).
Original four handoff archives remain byte-preserved; new evidence is supplemental.
The deleted remote recovery branch is not recreated.
