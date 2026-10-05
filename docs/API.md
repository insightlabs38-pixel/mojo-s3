# API guide and compatibility policy

The development version is **0.1.0-dev**. This identifies unreleased work, not a
release candidate. Linux x86-64 and Mojo 1.1.0 are the qualified baseline. Common store, configuration, result, range and pagination types are also
re-exported from `mojo_s3`. Detailed provider and transport APIs remain in their
modules.

## Public API review

The table names the intended stable public surface for the first 0.1 release.
Until that release, source compatibility can change with a documented migration.
No Mojo binary ABI compatibility is promised.

| Classification | Surface | Contract |
|---|---|---|
| Public, intended stable | `client.S3Store`; `objects.ObjectStore` | Synchronous object operations described below |
| Public, intended stable | `config.S3Config`; `signing.Credentials` | Explicit configuration and static credential values |
| Public, intended stable | `objects.PutOptions`, `ListOptions`, `ObjectRange` | Operation-specific options; range bounds are inclusive |
| Public, intended stable | `objects.GetResult`, `PutResult`, `ObjectMetadata`, `ObjectInfo`, `ListResult` | Owned results and opaque service identifiers |
| Public, intended stable | `errors.S3Error`; `S3Store.last_error` | Request-associated diagnostic detail alongside standard Mojo `Error` |
| Public, intended stable | `protocol.Field` | Name/value pairs for metadata and advanced signed headers |
| Public, intended stable | `S3Store.presign`, `upload_file`, `download_file` | S3 capability and synchronous file transfers |
| Public, intended stable | `objects.ListPaginator`, `credentials.StaticCredentials`, `EnvironmentCredentials`, `SharedFileCredentials` | Bounded raw pages and owned static credential snapshots |
| Experimental | `credentials.CredentialProvider`, `transfers.TransferManager`, `TransferOptions` | Provider extension and file transfer policy; refresh, cancellation and progress are not implemented |
| Experimental | `http.CurlTransport` constructor and moving it into `S3Store` | Transport tuning; backend-specific customization |
| Experimental | `multipart.CompletedPart`, `initiate`, `upload_part`, `complete`, `abort`, `multipart_upload_file` | Explicit upload lifecycle and cleanup responsibilities |
| Experimental | `concurrent.concurrent_multipart_upload_file` | Bounded Linux pthread upload; dynamic race qualification pending |
| Experimental | `crypto.bytes_of` | Convenience UTF-8 conversion; ordinary payloads are `List[UInt8]` |
| Internal | `S3Store.request`, `timestamp`, checksum helpers; transport `send`, `option`, handles/callbacks | Implementation plumbing, not an extension API |
| Internal | Other signing/protocol/crypto/XML/files/retry helpers; worker structs and `_fail_after` | Deterministic fixtures and implementation details |

Modules being importable does not make every symbol a supported API. Configuration
and result fields listed here are public; native handles and callback state are
internal. Future backends should implement the small `ObjectStore` trait, rather
than inherit S3 signing, presigning or multipart behavior.

For released 0.x versions, patch releases preserve the documented public source
API and behavior except corrections to invalid or insecure behavior; minor
releases may introduce breaking changes with changelog/migration notes.
Experimental APIs may change in patch releases, with changes recorded. Internal
APIs have no compatibility guarantee. A future 1.0 requires mature API and
platform qualification. `.mojoc` packages must be rebuilt for their consuming
Mojo version; a SemVer-compatible SDK release does not imply compiler ABI compatibility.

## Common operations

| Call on `S3Store` / `ObjectStore` | Returns | Notes |
|---|---|---|
| `put(bucket, key, data, options=PutOptions())` | `PutResult` | Binary `List[UInt8]`; overwrites existing object |
| `get(bucket, key)` | `GetResult` | Buffered bytes and metadata |
| `head(bucket, key)` | `ObjectMetadata` | No object payload |
| `exists(bucket, key)` | `Bool` | False only for an HTTP not-found category; other failures raise |
| `delete(bucket, key)` | Nothing | Service delete semantics; no bucket deletion |
| `list(bucket, options=ListOptions())` | `ListResult` | One ListObjectsV2 page |
| `get_range(bucket, key, ObjectRange(start, end=-1))` | `GetResult` | Inclusive bounds; `-1` requests through EOF |

`PutOptions(content_type="application/octet-stream")` owns a `metadata` list of
`Field` values. Supply metadata names without `x-amz-meta-`. `ListOptions` accepts
`prefix`, `delimiter`, `max_keys` (1–1000), and `continuation_token`. Pass
`ListResult.next_token` unchanged to the next call while `truncated` is true.
`prefixes` contains delimiter groups. Raw object keys are UTF-8 names: do not URL
encode or normalize slashes/dot components before passing them to the SDK.

`ObjectMetadata.size` is the full object size even for a ranged GET; use
`len(result.data)` for the selected byte count. ETags and version IDs are opaque
service strings, not locally computed content digests. `checksum_verified` is
true only when supported returned checksum data was actually validated. HEAD
metadata alone does not prove integrity.

## Ownership and errors

A store owns a move-only libcurl transport and copies its configuration. A custom
transport is transferred with `S3Store(config, transport^)`. Use one store per
execution context; simultaneous calls on one store are unsupported. Result lists
and strings own their values and do not borrow libcurl buffers. Large buffered
PUTs/GETs can create additional payload copies; use file transfers for large data.

Operations raise standard Mojo `Error`, not typed S3 exception subclasses.
After a request failure, inspect `store.last_error` for HTTP status (0 for
transport), S3 code, message, IDs, resource and category. Categories currently
include `NotFound`, `SignatureMismatch`, `ExpiredRequest`, `AccessDenied`,
`InvalidRange`, `PreconditionFailed`, `ServerFailure`, `InvalidRequest`,
`Timeout`, `TransportFailure`, and `DataIntegrity`.

`last_error` is request-associated state, not a guarantee for every raised error.
Local validation, parsing and filesystem failures may have no structured detail;
validation before a request can leave earlier state. A new request clears it and
a successful retry clears earlier attempt errors. `exists` can return false while
retaining the not-found detail. `presign` performs no request and does not clear
it. Consume diagnostic state immediately and keep the raised error as the primary
failure signal. No operation automatically logs credentials or request bodies.

See [configuration](CONFIGURATION.md), [credentials](CREDENTIALS.md),
[transfers](TRANSFERS.md), and [security](SECURITY.md).

`ObjectRange.suffix(n)` requests the final positive `n` bytes, clamping to the
object length. `ListPaginator(bucket, options)` retains only continuation state;
call `next_page(store)` while `done` is false. Returned pages remain owned and
raw server tokens remain available. Non-advancing tokens and a configurable
`max_pages` ceiling fail explicitly.
