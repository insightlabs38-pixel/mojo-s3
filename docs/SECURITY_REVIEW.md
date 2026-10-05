# Local source security review — October 4, 2026

Scope: the native SDK and new credential/range/pagination/transfer source on the
local release-readiness branch, reviewed with ordinary/ASan fixtures and local
S3 backends. This is a direct source review, not a formal Codex Security scan:
the scan integration's start/preflight tools were unavailable in this workspace.
No formal scan artifact or exhaustive audit is claimed. No upstream reports were
submitted. No validated critical vulnerability was identified in this review.

| Reviewed boundary | Evidence and conclusion |
|---|---|
| Credentials/signing/logging | SDK source does not automatically log request credentials, Authorization or presigned URLs. Local providers resolve owned snapshots, fail incomplete credentials, reject control characters and bound profile files to 1 MiB. Tests use synthetic identities. Strings are not secure-memory storage. |
| HTTP/header injection | Endpoint parsing restricts HTTP(S), rejects embedded user information/query/fragment and invalid controls; request/header validation and signing fixtures cover newline/whitespace and path encoding. Redirects remain disabled. |
| TLS and worker propagation | Peer/hostname verification is enabled by default. Custom trust and explicit insecure mode are separately tested. Worker stores inherit TLS/trust/timeouts; verified virtual-host HTTPS exercises the worker path. |
| Remote input | Curl body/header callbacks enforce buffer limits and contain exceptions across the C ABI. XML input/depth/nodes are bounded, DTD/entity references rejected, and network loading disabled. Malformed/non-XML error responses preserve HTTP failure. Properties and fault fixtures cover invalid UTF-8, entities, depth, duplicates and size ceilings. |
| File integrity/paths | Secure temporary files are created beside the destination; length and supported full-object SHA256 are validated before fsync/atomic rename. Corruption/transport failure preserves the destination. Callers choose trusted paths and keep upload sources stable. No source locking, directory fsync or disk quota enforcement is promised. |
| Multipart/native threads | Worker count/part size/count are bounded; contexts/results are preallocated before launch, outcomes occupy disjoint slots, cancellation flag is atomic, and parents read after joining every launched worker. Exceptions stay inside the worker C ABI. Failure/partial launch/embedded completion fixtures verify join-before-abort and error preservation under ASan. Cleanup failure exposes an orphan upload ID. |
| New range/pagination/transfer paths | Suffix ranges require positive lengths and coherent 206/Content-Range/body lengths; tokens stay opaque, nonadvancing tokens fail, and page count is bounded. Transfer options validate before bounded multiplication. The part-buffer budget is not a total RSS ceiling; copies/native overhead remain documented. Live roundtrips exercise all upload selections. |
| Error and retry state | New requests clear prior structured state; request failures and retries retain correct diagnostics. Local validation can leave earlier state, now documented. Retries are bounded/classified and unsafe operations are not replayed automatically. |

The unchanged SDK baseline also passed an isolated matching-nightly TSan gate,
intentional-race control and live checks. This supports the tested concurrency
paths; it neither proves race freedom nor qualifies Mojo 1.1.0's packaged runtime.

Remaining review limits: no actual AWS identity/bucket, ARM64/macOS execution,
long-running fuzz campaign, independent penetration assessment, formal scan, or
all native dependency internals. Native dependencies require OS security updates.
Hosted baseline CI passed; phase-2 evidence is in RELEASE_READINESS.md. Secure zeroization and operation-wide deadlines remain future work. Native
refresh/cancellation additions are reviewed/tested experimental surfaces, not a
formal audit. See [SECURITY.md](SECURITY.md) for application responsibilities.

## Phase-2 bounded review

Credential endpoint trust/timeouts/64KiB parser limits, expiration/fail-closed
refresh/copy ownership, typed headers, batch outcome identity, copy embedded
errors, ETag/version-pinned ranges, coordinator callbacks, joins-before-abort and
fsync/atomic replacement received direct review and deterministic faults. No
credential is logged. Local synthetic fixtures do not replace workload identity
or KMS authorization testing on AWS. The unsuppressed intermittent OpenSSL TSan
warning is retained, so native dependency race qualification is incomplete.
