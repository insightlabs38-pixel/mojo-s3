# Phase-2 API and qualification boundary

Mojo-S3 remains a native S3 data-plane SDK. No Python interpreter or subprocess is
used by runtime code. Python is used only for test orchestration and reference
oracles. Version remains **0.1.0-dev**; these additions are not a released API.

## Data plane

`S3Store.copy_object(source_bucket, source_key, bucket, key, CopyOptions())`
supports encoded source keys, opaque source version IDs, source conditions and
COPY/REPLACE metadata behavior. `CopyResult` exposes ETag/date/version IDs. An
HTTP-200 embedded error is still an error. Conditional destination copy is refused.

`delete_objects(bucket, List[ObjectIdentifier])` accepts 1..1000 unique key/version
identifiers and sends Content-MD5. `BatchDeleteResult.deleted` and `.errors` expose
every outcome; `.all_succeeded()` never hides partial failure. Missing, duplicate
or unrequested outcomes are rejected. Copy and batch deletion are not retried
automatically because their commit/version semantics are ambiguous.

`head_bucket` and `bucket_exists` provide onboarding checks; only NotFound means
absence. Authorization failures propagate. `ReadOptions` adds versionId, expected
bucket owner, and `Conditions` for GET/HEAD/ranges. Conditions cover If-Match,
If-None-Match, If-Modified-Since and If-Unmodified-Since. PUT supports only the
first two; multipart rejects conditions rather than silently dropping them.
DELETE accepts version and expected owner but currently rejects conditions.

`PutOptions` adds content disposition/encoding/language, cache control, metadata,
tags, storage class, expected bucket owner, and AES256/aws:kms/aws:kms:dsse request
headers. KMS key IDs require a KMS mode. SSE-C is deferred because it needs a
separate secret-handling contract. Local fixtures validate KMS/DSSE construction;
no actual AWS KMS permission/encryption qualification is claimed.

## Credentials (experimental)

Static explicit/environment/shared-file resolution stays unchanged.
`CredentialSource`, `CredentialSnapshot`, `CredentialCache` and
`S3Config.with_provider(...)` add native Web Identity STS, container credentials
and IMDSv2. `workload_source_from_env()` is explicit network opt-in; the ordinary
default chain never silently contacts instance metadata. IMDS additionally
requires `S3_ALLOW_IMDSV2=1` and respects AWS_EC2_METADATA_DISABLED.

Snapshots carry UTC expiration. A cache refreshes when remaining lifetime is at
most 300 seconds (configurable 0..3600); an expired/too-short snapshot or refresh
failure fails closed. Every signing attempt obtains a snapshot, including retries.
Each copied worker config owns its own cache; no shared/global mutable credentials.
Presigning now requires mutable store ownership and refuses a URL lifetime longer
than a workload snapshot's remaining validity. Static credentials have no known
expiration, so callers remain responsible for session lifetime.

HTTPS verifies certificates. Responses are bounded at 64 KiB; requests have a
5-second total/1-second connect timeout. No credential logging. JSON accepts flat
string fields; expiration accepts second-resolution UTC `YYYY-MM-DDTHH:MM:SSZ`,
not fractional/offset forms. IMDS never falls back to v1. HTTP production trust is
restricted to documented metadata IPs; HTTP loopback is only an explicit
`local_fixture=True` test opt-in. An explicitly supplied HTTPS endpoint is trusted
by its caller; do not accept it from untrusted input. AssumeRole, SSO and
credential_process are deferred.

## Integrity

SHA256, SHA1, CRC32 and CRC32C support buffered/file PUT and supported full-object
GET verification. Metadata separates algorithm, supplied value, checksum type,
verification bool, and checksum_state (`absent`, `unverified`, `verified`,
`composite`, `unsupported`). CRC64NVME is retained as unsupported. Composite
multipart checksums and part-count suffixes are never treated as full-object
checksums. No multipart-combination algorithm is promised; ETag remains an opaque
identity/condition token, never MD5. Content-MD5 on batch XML is a protocol checksum.

## Transfers (experimental additions)

TransferManager retains basic, low-level multipart/range, and policy layers.
Ordinary uploads select streaming/sequential/concurrent multipart by threshold.
Large downloads now partition deterministic closed ranges across 1..16 independent
workers and preserve HEAD ETag/version identity. Each range is validated then
written with pwrite into a private temporary file. All workers join, size and
supported whole-object checksum are checked, then fsync/atomic replacement occurs.
Failures leave an existing destination unchanged and remove the staging file.
Buffer budgeting excludes curl copies/native allocators and bounded per-range
outcome metadata (up to 1,000,000 outcomes); it is not a total-RSS ceiling.

`TransferControl`, `TransferProgress`, `ProgressObserver` are experimental.
Observers run on the coordinating thread with copied counters, never worker
contexts. Cancellation stops new work; active HTTP requests finish or time out;
all threads join before returning. Callback errors cancel and join safely.
Nonempty controlled uploads always use multipart, including below threshold, so
cancellation can abort before CompleteMultipartUpload. No cancellation can roll
back an already committed completion/empty PUT. Keep the control/observer alive
and unmoved throughout the synchronous call; callbacks may cancel via a borrowed
pointer as demonstrated in tests. One control belongs to one operation. Arbitrary
cross-thread mutable aliasing is not a supported public ownership contract.
Linux pthread_tryjoin_np currently limits this path to Linux.

Generic caller-provided stream traits are deferred: curl callbacks cross C ABI,
must retain owned source/sink lifetimes and contain Mojo exceptions. A broad I/O
framework would add more risk than the proven byte/file APIs at this stage.

## Endpoints and diagnostics

Regional AWS and China endpoints use virtual hosting by default; generic endpoints
remain explicit. `aws_endpoint(region, dual_stack, fips)` constructs ordinary
commercial/GovCloud and China dual-stack forms; China FIPS is refused. Access
points, S3 Express, accelerate and isolated partitions are deferred. These flags
are request-construction coverage, not live AWS qualification. Redirects are not
followed with a mismatched signature: S3Error exposes RegionMismatch and
bucket_region, alongside status/code/request/host IDs. Bounded retries retain the
final structured failure, attempt count and retry_exhausted state. Requests identify `mojo-s3/0.1.0-dev` without credentials.

## API stability

Existing byte/file/CRUD/range/list/presign/static credentials are the stable
candidate layer. New typed data-plane/options/checksum APIs are release candidates
pending AWS qualification. Refresh, progress, cancellation and concurrent download
remain experimental. Provider parsers, worker contexts, launch/write failure hooks,
checksum combinators and raw FFI are internal implementation/testing details.

## Reference specifications

- [CopyObject](https://docs.aws.amazon.com/AmazonS3/latest/API/API_CopyObject.html)
- [DeleteObjects](https://docs.aws.amazon.com/AmazonS3/latest/API/API_DeleteObjects.html)
- [Object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html)
- [Web Identity STS](https://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRoleWithWebIdentity.html)
- [Container provider](https://docs.aws.amazon.com/sdkref/latest/guide/feature-container-credentials.html)
- [IMDSv2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/configuring-instance-metadata-service.html)

Specification copies and local execution evidence are retained outside SDK history
in the separate runtime-investigation workspace. Live AWS has not been executed.
