# Transfers and integrity

All current transfers are synchronous. Use buffered `put` / `get` for small
objects and `S3Store.upload_file` / `download_file` for large ones. There is no
automatic multipart threshold or transfer-manager abstraction yet.

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

The file helpers default to 8 MiB parts, accept 5–64 MiB parts and at most 10,000
parts, and use ordinary PUT for empty files. A final part may be smaller than
5 MiB. The sequential helper keeps one part active. The concurrent helper accepts
1–16 workers and uses at most the part count. Each worker owns its transport,
store, descriptor and payload buffers. Payload memory is approximately two part
buffers per active worker, plus transport/signing/result overhead; this is not a
strict process RSS limit. Buffered PUT/GET similarly can have additional copies.

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
ranges; suffix ranges and file range downloads are pending.

Concurrent downloads, cancellation, progress callbacks, automatic multipart
selection and resumable uploads are not currently implemented. Use independent
stores for application-managed parallel object operations and bound memory and
worker counts explicitly.

## Transfer manager

`TransferManager(store^, TransferOptions(...))` owns a store and selects file
upload mode automatically. Files below `multipart_threshold` use streamed PUT;
nonempty files at or above it use sequential multipart with one worker or the
existing concurrent helper with multiple workers. Empty files use ordinary PUT.
Downloads use the existing streamed, verified, atomic replacement operation.

Defaults are a 64 MiB threshold, 8 MiB parts, four workers, and a 64 MiB configured
part-buffer budget. Parts must be 5–64 MiB and workers 1–16; invalid settings and
`workers * part_size > max_in_flight_bytes` fail before scheduling. This budget
counts part data only: signing/request copies, per-worker response ceilings,
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
unchanged during upload. Cancellation, progress callbacks, concurrent ranged
downloads and resumable state remain future work; low-level operations stay
available.
