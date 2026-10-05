# Transfers and integrity

All current transfers are synchronous. Use buffered `put` / `get` for small
objects and `S3Store.upload_file` / `download_file` for large ones. The experimental
TransferManager selects streaming or multipart uploads by threshold.

`upload_file(bucket, key, source, options=PutOptions())` hashes a seekable file in
64 KiB chunks, then streams it via libcurl. It returns `PutResult`. Keep the source
unchanged until the call completes, including retries. The SDK does not lock it.
`download_file(bucket, key, destination)` returns `ObjectMetadata`. It stages a
mode-0600 temporary file beside the destination, verifies received length and any
supported checksum, fsyncs the file, then renames it over the destination. Failure
before commit removes the temporary file and preserves the prior destination.
The destination directory must be writable; a successful download replaces an
existing destination. The parent directory is not fsynced, so atomic replacement
is not a promise of directory-entry durability after a machine crash.

## Multipart

```mojo
from mojo_s3.multipart import multipart_upload_file
from mojo_s3.concurrent import concurrent_multipart_upload_file

# Inside a raising function, with store already configured:
var sequential = multipart_upload_file(store, "bucket", "large.bin", "source.bin")
var parallel = concurrent_multipart_upload_file(
    store, "bucket", "other.bin", "source.bin", concurrency=4,
    part_size=8 * 1024 * 1024,
)
```

The file helpers default to 8 MiB parts, accept 5 MiB–5 GiB target parts and dynamically increase the part size to
keep at most 10,000 parts, and use ordinary PUT for empty files. A final part may be smaller than
5 MiB. The sequential helper keeps one part active. The concurrent helper accepts
1–16 workers and uses at most the part count. Each worker owns its transport,
store, descriptor and bounded stream buffers. File-range hashing and upload reads use
64 KiB chunks rather than allocating entire parts; transport/signing/result
overhead also consumes memory. This is not a strict process RSS limit. Buffered PUT/GET similarly can have additional copies.

Workers stop queuing after failure and every started worker joins before abort
or context cleanup. The parent store cannot be used simultaneously elsewhere.
AddressSanitizer checks and fault tests cover failure cleanup; TSan compilation
works but the released Mojo runtime fails before user main. Dynamic race
qualification remains pending; see [TSAN.md](TSAN.md).

Low-level `initiate`, `upload_part`, `complete`, and `abort` remain available.
Callers own upload cleanup and S3 part-size compliance. Completion sorts and
validates the part manifest and recognizes Error XML inside HTTP 200. Helpers
abort on failure and preserve the primary request error. If abort also fails, the
raised error includes the orphan upload ID: record it securely for later cleanup.
No resumable state is stored. A lost completion response can leave the outcome
ambiguous; initiation/completion are not automatically retried.

## Checksums and ranges

Set `config.request_checksums=True` before constructing a store to send SHA-256
for ordinary PUT/upload_file and request available checksums for GET/download_file.
Supported returned full-object SHA-256 is checked even when negotiation is off.
A mismatch raises and prevents staged download commit. Metadata records supplied
checksum/algorithm and `checksum_verified` separately.

Multipart composite checksums and unsupported algorithms are retained without
verification. Negotiation does not currently add multipart checksum support.
ETag is not an MD5 promise. A range response is not compared to a full-object
checksum. `ObjectRange(start, end=-1)` supports closed and open-ended inclusive
ranges; suffix ranges and concurrent file range downloads are available.

Resumable state and generic source/sink traits are not implemented. Automatic
multipart selection is available through TransferManager. Use independent
stores for application-managed parallel object operations and bound memory and
worker counts explicitly.

## Transfer manager

`TransferManager(store^, TransferOptions(...))` owns a store and selects file
upload mode automatically. Files below `multipart_threshold` use streamed PUT;
nonempty files at or above it use sequential multipart with one worker or the
existing concurrent helper with multiple workers. Empty files use ordinary PUT.
Downloads use bounded validated ranges and atomic destination replacement.

Defaults are a 64 MiB threshold, 8 MiB parts, four workers, and a 64 MiB configured
buffer budget. Target parts must be 5 MiB–5 GiB and workers 1–16. The manager forces multipart above 5 GiB even if the configured threshold is
larger. Upload
validation requires at least 64 KiB per worker, independent of protocol part size.
Download planning bounds ranges to 64 MiB, total range buffers to the budget,
and scheduling to one million ranges, reducing workers or increasing ranges
when needed. A budget too small for a huge ranged download fails before workers
start; the low-level streamed download remains available. This budget excludes
signing/request overhead, per-worker response ceilings,
OpenSSL/libcurl state and allocator overhead add to RSS. It is not a process
memory cap. The existing 10,000-part ceiling and cleanup semantics apply.

```mojo
from mojo_s3 import S3Store, S3Config, TransferManager, TransferOptions

# Inside a raising function with an authorized existing bucket/source:
var manager = TransferManager(S3Store(S3Config.from_default()), TransferOptions())
_ = manager.upload_file("bucket", "artifact", "/path/to/artifact")
_ = manager.download_file("bucket", "artifact", "/path/to/destination")
```

The layer is experimental and has one active owner. Inspect
`manager.store.last_error` immediately after request failures. Keep sources
unchanged during upload. Progress/cancellation and concurrent ranged downloads are now experimental
([PHASE2.md](PHASE2.md)); resumable state remains future work; low-level operations stay
available.

## Phase-2 transfer controls

Large manager downloads now use validated deterministic ranges into one temporary
file, join all workers, verify final size/checksum, fsync and atomically replace.
Progress observers run on the coordinator; callback failure cancels work and joins
before cleanup. Nonempty controlled uploads use multipart to support pre-commit
abort. See [PHASE2.md](PHASE2.md) for lifetime, buffer-budget and commit boundaries.


## Convergence additions (experimental)

`plan_multipart(size_bytes: Int64, target_part_bytes)` plans without allocating
payloads. Its protocol capacity is 10,000 × 5 GiB (about 48.8 TiB); source and
service limits still apply. It validates negative sizes, overflow and target
bounds. Files must remain unchanged through hashing, upload and retries.
`upload_part_file` streams a specified file range. Synthetic boundary tests are
separate from provider acceptance; the local wide wire oracle exercised a real
5 GiB part and a 7-byte tail without allocating part-sized buffers.

`TransferManager.copy_object` uses ordinary CopyObject through 5 GiB, then
server-side multipart copy. `multipart_copy_object` explicitly forces the latter
for nonempty objects. Source version/ETag is pinned, every part sends a signed
copy range and no source payload, and failures attempt abort while retaining the
primary structured error. Metadata COPY preserves returned common metadata;
REPLACE uses caller values. `CopyOptions.tagging_directive` independently selects
COPY or REPLACE. COPY requires GetObjectTagging; REPLACE with an empty tag list
clears tags. Destination tags with COPY are rejected before mutation. Destination
conditional PUT options remain unsupported for multipart initiation.

`list_parts` / `PartsPaginator` and `list_multipart_uploads` /
`MultipartUploadsPaginator` expose bounded pages, fail on malformed entries or
nonadvancing markers, and never abort discovered uploads. Upload IDs and ETags
are opaque; retain them exactly. These inspection APIs do not constitute safe
resume by themselves; see [RESUME_DESIGN.md](RESUME_DESIGN.md).

Observers run on the coordinator and can request cancellation by returning true
from `cancel_requested()` after `on_progress`. They do not need an unsafe pointer
to TransferControl. State, stop flags, contexts and exclusive worker outcomes
live in preallocated owned heap storage until every started worker joins.
Download result storage scales with worker count, not range count. Cancellation
observed before rename/completion aborts or removes staging; a committed success
is returned as success. Cancellation cannot promise rollback of a completed S3
object. Cancellation does not interrupt an in-flight libcurl request; configured
timeouts bound that wait.

## Final convergence review

RC preparation changes no planner, stream body, offset or file hashing path. The preserved 5 GiB + 7-byte wire control therefore remains the large-object evidence; it was not rerun. Current backend copy/tag/range and version-listing limitations are in COMPATIBILITY.md. Resume and multipart checksum negotiation/composition remain deferred; CRC64NVME_DESIGN.md records the bounded design assessment.
