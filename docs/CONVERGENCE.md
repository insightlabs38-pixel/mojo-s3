# Preserved convergence checkpoint — October 5, 2026

This records `sdk/s3-phase2` at `1e93cb3`; final preparation updates are in
[RC_CONVERGENCE.md](RC_CONVERGENCE.md). Backend claims below are historical for
the tested versions; current release evidence is in COMPATIBILITY.md.

Keep **0.1.0-dev** on `sdk/s3-phase2`. No main merge, tag, publication, upstream
issue or PR is authorized or performed. Core supported platform remains Linux
x86-64 / Mojo 1.1.0; all added transfer/provider/lifecycle interfaces are
experimental, with classifications in API.md. Research sources and runtime
reconstruction are outside SDK history.

## Implemented and reviewed

- Allocation-free Int64 multipart planner through 10,000 × 5 GiB (about 48.8 TiB),
  dynamically raising target part size within protocol bounds. The manager forces
  multipart above the single-copy/PUT size even with a larger configured threshold.
- File-range SHA hashing and HTTP uploads stream bounded 64 KiB chunks; no entire
  part allocation. A real sparse 5 GiB part plus 7-byte tail passed an independent
  wire/hash/offset oracle with about 13.5 MiB sampled native RSS. This is correctness
  and bounded-memory evidence, not full-capacity AWS throughput.
- Downloads retain heap-owned state/stop/context allocations until all launched
  workers join. Exclusive outcome storage scales with workers, not range count.
  Progress is monotonic and bounded; safe observers request cancellation without
  an unsafe alias to a coordinator variable. Near-completion cancellation preserves
  the destination; cancellation after server completion returns success without
  aborting the committed object. Cancellation waits for active requests/timeouts.
- Server-side multipart copy pins source ETag/version, copies ranges without source
  payloads, preserves common metadata and explicit tag policy, rejects malformed /
  embedded failure results and preserves the primary error through abort failure.
- Bounded ListParts/ListMultipartUploads pages and explicit paginators validate
  identity/count/order/markers. Inspection never aborts discovered uploads.
- Version-aware get/put/delete object tags use escaped XML and PUT Content-MD5.
  COPY and REPLACE tag directives are independent of metadata, including empty
  replacement. Actual local version tests isolate tag mutations and copy the
  requested source version; explicit version cleanup leaves no retained versions.
- Signed native ordinary AssumeRole uses an owned one-hop source provider and
  independent refresh caches, source tokens, regional HTTPS/TLS, external ID,
  duration bounds, bounded responses and structured credential-refresh failures.
  Role chaining/cycles and implicit source_profile role resolution are rejected.

## Evidence and limits

The full ordinary check covers precompile, native units/properties, new planner
and root-facade consumers, deterministic protocol/fault/signature/TLS fixtures,
AWS-harness compilation and examples. Source installation additionally compiles
the public consumer outside the repository. CI runs these checks and the new
MinIO contracts/ASan fixtures. Inspect the completed CI conclusion for the exact
pushed revision, rather than extrapolating from a prior green commit.

Local fault oracles separately cover short/wrong ranges, checksum mismatch,
read-only writes, partial launches, callback failures, pre/active/near-end
cancellation, malformed multipart listings and tags, oversized part sizes,
HTTP-200 copy/completion errors, primary-error retention and explicit orphan
reporting. A late-cancellation monitor waits until the fake server commits before
cancelling, then verifies success, no abort and worker/monitor joins.

MinIO passed streamed/concurrent/manager workflows, repeated downloads with
1/2/4/8/16 workers, tiny/empty/odd/exact range boundaries, tag policy and version
fixtures. Its pinned release deviates for multipart prefix/MaxUploads/order and
Unicode tags; the native inspection workflow tests an explicitly isolated
single-upload supported subset. Strict pagination remains enforced.

ZEROS3's UploadPartCopy returns HTTP200 with an empty body and empty copy result,
independently captured through boto3; native multipart copy correctly fails.
Historical Versity 1.0.16 accepts tags through PutObjectTagging but rejects the equivalent encoded
header during multipart initiation, independently reproduced through boto3.
Their combined new contracts are not qualified as passing. Existing baseline
contracts remain distinct; Versity 1.8.0 passes the old tagging and If-Match cases; see RC_CONVERGENCE.md for current limits.

ASan and an isolated nightly TSan closure exercise the new faults and local
version/copy paths. The unchanged strict TSan gate passes with genuinely aware
AsyncRT/Support, matching nightly CompilerRT, rebuilt LLVM main and instrumented
OpenSSL. Twenty cold hello runs, fifty cold synchronized smoke runs, a genuine
Mojo race report, TLS and workload refresh controls pass. This neither qualifies
released Mojo TSan nor proves race freedom of all native dependencies.

Independent C and std-only Mojo OpenSSL probes distinguish invisible acquire /
release synchronization in uninstrumented hash tables from a separate first-
allocation allow_customize race in instrumented OpenSSL 3.5.7. Cold EVP reports
reproduce without the LLVM patch. Drafts and invalid initial probe lifetime
controls are preserved outside SDK history; no suppression or warm-up changed the
supported gate. LLVM's rebased narrow mmap regression and nearby tests pass actual
static/dynamic lit (8/8); public Modular packaging candidate is not a demonstrated
private production-selector repair. tcmalloc remains a configuration constraint.

## Explicit deferrals

Persisted resume is deferred until source identity, crash-safe records and server
part reconciliation have independent oracles; RESUME_DESIGN.md specifies those
invariants. This checkpoint deferred version listing; RC preparation now provides an
experimental bounded version/delete-marker page and paginator API. No inferred safe resume or automatic cleanup
of other uploads is introduced. A lost initiation response can leave an unknown
upload ID, and a lost completion response can leave an ambiguous commit; neither
is resolved by scanning/aborting unrelated uploads.

Current AWS documentation confirms 48.8 TiB, 10,000 parts and 5 MiB–5 GiB parts.
Its checksum table permits CRC32/CRC32C full-object or composite multipart checksums,
CRC64NVME full-object only, and SHA1/SHA256 composite only. Multipart negotiation,
per-part checksum manifests and composition are deferred: simply hashing a full
file does not verify a SHA multipart composite. No combination algorithm ships
without protocol/lifecycle and independent service oracle coverage. CRC64NVME and
newer algorithms are unimplemented; supplied supported full-object digests and
explicit composite/unverified states retain their existing behavior. ETag remains
opaque and never implies MD5 integrity.

No live AWS credentials were available. The expanded explicitly authorized
existing-bucket/prefix harness compiles; real AWS, KMS/DSSE, cross-account policy,
ARM64/macOS and public runtime distribution remain unqualified. Local versioned
MinIO setup is fixture orchestration, not AWS account administration. Benchmarks
are repeated loopback observations with documented startup/cache/compiler-load
and RSS sampling limits, not portable production performance claims.
