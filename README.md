# mojo-s3

A native Mojo object-storage library with an S3 backend. The SDK executes compiled
Mojo code and calls libcurl, OpenSSL, and libxml2 through Mojo's C FFI. Client
operations do not use Python, boto3, subprocesses, or a custom HTTP/TLS stack.

This is an early implementation with verified interoperability, **not yet a
production-ready release**. The current target is Linux x86-64 and Mojo 1.1.0.

## Implemented and verified

- Provider-neutral `ObjectStore` trait: PUT, GET, HEAD, exists, DELETE, list, ranges.
- Explicit/environment credentials, including session-token signing fixtures.
- Path-style addressing; virtual-host construction tested with fixtures.
- SHA-256/HMAC bindings and deterministic SigV4, including 64 botocore comparisons.
- Binary-safe CRUD, metadata, ListObjectsV2 pagination and delimiter prefixes.
- Closed and open-ended ranges with Content-Range validation.
- Presigned GET/PUT, including signed metadata constraints and tampering tests.
- Bounded buffered responses, reusable connections, TLS verification and custom CA
  trust, connection/total timeouts, and redirects disabled.
- File streaming with incremental upload hashing and atomic download replacement.
- Multipart initiation, parts, sorted completion, abort, and a file upload helper.
- Central retry decisions, full-jitter backoff, delta/date Retry-After, and safe replay.
- Bounded native pthread multipart (1–16 workers), joined before cleanup.
- Opt-in SHA-256 checksum negotiation and full-object integrity validation.
- Structured `S3Error` retained in `store.last_error` after operations raise.

[Compatibility](docs/COMPATIBILITY.md) records actual results against MinIO and
Versity Gateway and ZEROS3. AWS S3 has not been tested. Live MinIO STS credentials
and ZEROS3 virtual-host HTTPS have also been verified.

## Build and test

Install Mojo 1.1.0 using its official compiler distribution. One supported route:

```sh
python3 -m venv .venv
.venv/bin/pip install mojo==1.1.0
export PATH="$PWD/.venv/bin:$PATH"
# Debian/Ubuntu native dependencies:
sudo apt-get install libcurl4-openssl-dev libssl-dev libxml2-dev openssl
scripts/check
```

Python packages provide compiler/formatter tooling and test orchestration only.
The built SDK executables have no CPython dependency. The native build script uses
`ldconfig` to discover libraries; `CRYPTO_LIBRARY`, `CURL_LIBRARY`, and
`XML_LIBRARY` can override their absolute paths. `MOJO` and `MBLACK` override
compiler/formatter commands.

Import from `src` with `mojo build -I src` and link those three native libraries,
or use `scripts/build`. `scripts/check` precompiles `build/mojo_s3.mojoc`, builds
examples and unit/fixture tests, and runs local transport-failure and TLS tests.
It requires no cloud credentials. Compiled packages are tied to Mojo 1.1.0.

## Usage

```mojo
from mojo_s3.client import S3Store
from mojo_s3.config import S3Config
from mojo_s3.signing import Credentials
from mojo_s3.crypto import bytes_of

var config = S3Config(
    "https://s3.example.com", "us-east-1",
    Credentials("access-key", "secret-key", ""),
)
var store = S3Store(config)
_ = store.put("bucket", "hello.txt", bytes_of("hello"))
var result = store.get("bucket", "hello.txt")
var metadata = store.head("bucket", "hello.txt")
var page = store.list("bucket")
store.delete("bucket", "hello.txt")
```

These statements belong inside a raising function. See the executable
[basic](examples/basic.mojo) and [advanced](examples/advanced.mojo) examples.

`S3Config.from_env()` reads `S3_ENDPOINT`, `S3_REGION`, `S3_ACCESS_KEY`,
`S3_SECRET_KEY`, `S3_SESSION_TOKEN`, and `S3_FORCE_PATH_STYLE` (default `true`).
Credentials also fall back to `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`,
`AWS_SESSION_TOKEN`; region falls back to `AWS_REGION`.

```sh
export S3_ENDPOINT=http://127.0.0.1:9000
export S3_REGION=us-east-1
export S3_ACCESS_KEY=your-test-access-key
export S3_SECRET_KEY=your-test-secret-key
export S3_TEST_BUCKET=your-isolated-test-bucket
scripts/build examples/basic.mojo build/basic
build/basic
RUN_S3_INTEGRATION=1 scripts/check
```

The integration suite writes under random prefixes and removes its objects. It
uses an existing bucket; it does not create/delete remote buckets. Use only a
bucket where test writes are authorized. Streaming/multipart tests additionally
require `S3_STREAM_SOURCE` and `S3_STREAM_DESTINATION`; use a deterministic 32 MiB
source to reproduce the seven-part test.

## Advanced operations

`PutOptions` carries content type and `List[Field]` user metadata. `ListOptions`
carries prefix, delimiter, max keys, and an opaque continuation token. Pass a
page's `next_token` to the next call while `truncated` is true.

`store.get_range(bucket, key, ObjectRange(start, end))` uses inclusive byte
bounds. Omitting `end` requests through EOF. Its returned metadata size is the
full object size; `len(result.data)` is the selected byte count.

`store.presign("GET" | "PUT", bucket, key, expires, extra_headers)` returns a
bearer URL. Expiration is 1–604800 seconds. Supply all signed headers when using
it. Treat the URL as sensitive and avoid logging it.

`store.upload_file(...)` hashes then streams a seekable file.
`store.download_file(...)` writes beside the destination using a secure temporary
file, validates length, fsyncs, and renames only after success. Sources must remain
unchanged during transfers. Downloads can replace an existing local destination.

`mojo_s3.multipart` exposes `initiate`, `upload_part`, `complete`, `abort`, and
`multipart_upload_file`. The helper defaults to 8 MiB sequential parts, accepts
5–64 MiB parts, and aborts after failures. An abort failure reports the orphan
upload ID. Low-level callers own multipart cleanup and part-size compliance.

`mojo_s3.concurrent.concurrent_multipart_upload_file(store, bucket, key, source,
concurrency=4, part_size=8*1024*1024)` runs 1–16 Linux pthread workers. Each owns its
S3 store, descriptor and buffers; workers stop queuing on failure, join, then abort.
Peak payload memory is approximately two part buffers per worker. This API does
not make a shared `S3Store` safe for concurrent calls.

Set `config.request_checksums = True` for ordinary PUT/upload_file to send a
SHA-256 checksum and for GET/download_file to request available checksums. Full
SHA-256 checksums are validated whenever returned, even without that option.
`ObjectMetadata.checksum`, `checksum_algorithm`, and `checksum_verified` expose
what the server supplied and whether it was checked. Composite multipart checksums
and unsupported algorithms are not validated; partial range bytes are never
compared to a full-object checksum. Corruption prevents atomic download commit.

For transport options, construct a `CurlTransport(timeout_ms, connect_timeout_ms,
max_response_bytes, verify_tls, ca_bundle)` and move it into `S3Store(config,
transport^)`. TLS verification defaults to true. Each store/transport has one
owner and must not be used simultaneously by multiple threads.

## Current limits and next work

The SDK has not completed production qualification. Remaining work includes an
AWS integration, general concurrent object/download transfer management, suffix
ranges, CRC/MD5 and composite checksum validation, cancellation, broader credential
providers, portability, and larger-scale fuzzing. ThreadSanitizer is blocked by a
Mojo allocator/TSan incompatibility reproduced on the host and two clean
userspaces; AddressSanitizer passes. [Diagnosis and strict runtime gate](docs/TSAN.md). Explicit pagination is available; an iterator convenience API is
pending. Errors use Mojo's standard `Error` plus structured `last_error` rather
than typed exception subclasses.

[Architecture](docs/ARCHITECTURE.md), [status and resume notes](docs/STATUS.md),
[development](docs/DEVELOPMENT.md), [local benchmarks](docs/BENCHMARKS.md), and the original [goal](docs/GOAL.md) explain
boundaries, validation, and remaining priorities.
