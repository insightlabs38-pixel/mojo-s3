# Historical baseline compatibility

Local tests on October 4–5, 2026 with synthetic local credentials. AWS credentials
were not attached. Results apply to the versions and cases listed, not every
S3-compatible server or all AWS behavior.

ZEROS3 was built with Go 1.27.0 from the public repository
[insightlabs38-pixel/zeros3](https://github.com/insightlabs38-pixel/zeros3) at commit
`f391b7e552f654f59ec23e3f46fadf3f60c1d97d`. No backend internals enter the SDK.

| Feature | MinIO 2025-04-22 | Versity 1.0.16 POSIX | ZEROS3 f391b7e | AWS |
|---|---|---|---|---|
| PUT/GET/HEAD/DELETE/exists | Passed | Passed | Passed | Untested |
| Binary/zero-byte/overwrite | Passed | Passed | Passed | Untested |
| Metadata/content type | Passed | Passed | Passed | Untested |
| List V2/prefix/delimiter/pagination | Passed | Passed | Passed | Untested |
| Reserved/Unicode/percent keys | Passed | Passed | Passed | Untested |
| Repeated slashes/dot paths/newline | Backend limitations | Backend limitations | Passed | Untested |
| Closed/open-ended ranges | Passed | Passed | Passed | Untested |
| Presigned GET/PUT | Passed | Passed | Passed | Untested |
| Tampering/expiry/wrong secret | Rejected correctly | Rejected correctly | Rejected correctly | Untested |
| 32 MiB streaming + SHA256 comparison | Passed | Passed | Passed | Untested |
| Multipart uneven tail/abort/one part | Passed | Passed | Passed | Untested |
| Native multipart with 1/2/4/8 workers | Passed | Passed | Passed | Untested |
| boto3 bidirectional 32 MiB transfer | Passed | Untested | Passed | Untested |
| Virtual-host HTTP and HTTPS | Untested | Untested | Passed | Untested |
| Live session-token credentials | Passed with local STS | Untested | Not supported by backend | Untested |
| Negotiated full-object SHA256/SHA1/CRC32/CRC32C | Passed | Untested | Untested | Untested |
| HeadBucket/copy metadata/batch delete | Passed | Sequence not reached | Passed | Untested |
| Typed If-Match GET rejection | Passed | FAILED: wrong ETag accepted | Passed | Untested |
| Version-aware GET/HEAD/copy/delete | Passed (local versioned fixture) | Untested | Untested | Untested |
| Concurrent download 1/2/4/8, odd/small/empty | Passed | Passed | Passed | Untested |
| Controlled multipart progress/cancel/abort | Passed | Passed | Passed | Untested |
| Web Identity/container/IMDSv2 refresh | Local deterministic fixtures | Local fixtures only | Local fixtures only | Untested |

MinIO is RELEASE.2025-04-22T22-12-26Z. The common contract includes spaces, +, %, ?,
#, &, =, Unicode, literal `%2F`, slash-separated and long keys, and verifies binary
contents, metadata, pagination and failure semantics. Header/path/signature/query
tampering and expiration are tested with presigned URLs.

The ZEROS3 extended-key suite proves repeated slash, dot/dot-dot components,
leading/trailing slash and newline names stay distinct through CRUD and LIST.
Virtual-host HTTPS tests use an explicit local CA with verification enabled and
include CRUD, listing, ranges, presigning and concurrent multipart. MinIO STS
credentials are issued only for the local fixture and passed directly to native
processes without logging credential values.

## Observed backend limitations

- MinIO rejects repeated-slash and newline keys with `XMinioInvalidObjectName` in
  this configuration.
- Versity POSIX coalesces `dir//file` with `dir/file` and rejects a 900-byte filename
  component (`KeyTooLongError`). SDK paths are preserved, not normalized to suit it.
- ZEROS3 permits NUL-containing keys through CRUD, but its LIST XML replaces the
  NUL with U+FFFD and does not provide the requested URL-encoded listing. boto3
  reproduces this loss. NUL-key listing compatibility remains blocked by backend
  behavior; the extended-key passing suite excludes that unsupported case.
- S3rver 3.7.1 was excluded from authentication qualification because its SigV4
  signature calculation is unimplemented.

Native HTTP fixtures prove `/a//../b%2F` is transmitted as `/a//../b%252F` without
normalization. AWS's published GET signature and 64 botocore 1.43.108 fixtures
match. Another 2,000 URI/query/XML property cases cover astral Unicode, whitespace,
entities, encoded keys, invalid UTF-8 and nesting/duplicate-element limits.

Independent fixtures verify worker bounds, joins-before-abort, preserved part
errors, embedded HTTP 200 completion errors, partial thread launch cleanup,
checksums/corruption, TLS trust, timeouts, connection reuse, and delta/date retry.
AddressSanitizer passes the worker failure suite and real MinIO multipart. Mojo
1.1.0 ThreadSanitizer aborts in tcmalloc before even a minimal print program runs,
with the same failure outside the sandbox and in clean Ubuntu 24.04/Debian 12
userspaces. Released-runtime dynamic race-sanitizer qualification remains blocked; an
isolated matching-nightly rebuilt-runtime experiment passed the unchanged
baseline gate and extended live checks. The strict
execution gate and traced allocator/interceptor diagnosis are in [TSAN.md](TSAN.md).


## Release-readiness refresh

The October 4 local continuation reran the updated common contract, including
suffix ranges (one byte and larger than the object) and `ListPaginator`, on
MinIO, Versity 1.0.16 POSIX and ZEROS3. All three transfer-manager selections
passed 32 MiB hash roundtrips on all three. Versity streaming and sequential/
concurrent multipart also passed in the refresh. ZEROS3 extended keys, streaming, sequential/concurrent
multipart, bidirectional boto3 interoperability and verified virtual-host TLS
passed again. MinIO local STS, full-object checksums and multiprocess stress
passed. ASan passed native threads, failure/cleanup, the updated common contract,
manager roundtrips, 1/2/4/8-worker multipart and verified HTTPS.

These historical baseline results use stable Mojo 1.1.0. The isolated TSan runtime evidence
uses the exact nightly and unchanged baseline specified in TSAN.md. These results do not qualify additional platforms or Versity checksum behavior.

The historical Versity 1.0.16 conditional test failed; current 1.8.0 rejects the wrong If-Match. No SDK
header was dropped to accommodate it. KMS/DSSE request construction is fixture
coverage only. Current LLVM isolated strict gate has an unsuppressed intermittent
OpenSSL warning; see RELEASE_READINESS.md. AWS harness: AWS_QUALIFICATION.md.

## Current stable requalification — October 5, 2026

GitHub release identities were fetched at execution time. MinIO is
RELEASE.2025-10-15T17-29-55Z (`9e49d5e7a648f00e26f2246f4dc28e6b07f8c84a`),
built from the exact release-tag source with Go 1.27.0 after its binary archive
returned HTTP 410. Versity is checksum-verified 1.8.0 Linux x86-64, build
`fd04bc1df2656298577b82667a4195c77f8c7563`. Latest does not mean floating CI.

| Focused feature | Current MinIO | Current Versity 1.8.0 |
|---|---|---|
| Multipart tags: ordinary, spaces, +, /, _, - | boto3 and native pass | boto3 and native pass; old 1.0.16 failure is historical |
| Multipart Unicode tag | InvalidTag in both clients | Both pass |
| Duplicate tags / invalid encoding | Reference rejection tested | Reference rejection passes; typed native tags reject duplicates and construct encoding internally |
| COPY / REPLACE / empty replacement | Native/reference pass | Native/reference pass |
| Wrong GET/source If-Match | Native/reference reject | Native/reference reject; old acceptance is historical |
| Multipart server copy/content | Native/reference pass | Native/reference pass |
| ListParts pages / immediate abort and completion absence | Reference/native supported subset pass | Reference/native pass |
| Multipart prefix / MaxUploads / ordering / markers | Still deviates: empty prefixed result, ignored bounds/markers and creation-order output | Prefix/bounds/key-only pass; paired upload marker returns InvalidArgument |
| Versioned tag isolation / explicit-version copy | Native/reference pass | Native/reference pass with POSIX versioning-dir configured |
| Version/delete-marker listing and pagination | Native/reference reserved, space, plus and Unicode keys pass after SDK decoding fix | First bounded page passes; continuation repeats the requested version and native strict parser rejects |

The current MinIO full ordinary native transfer/range/copy/tag/version suite is
qualified separately from the old hosted CI pin. The old pin is retained because
the newest stable still fails the full strict multipart-listing contract. No SDK
validation is relaxed. The SDK's shared encoded-listing decoder now matches botocore's unquote_plus:
a bare '+' is a space and '%2B' is a literal plus. Raw unencoded keys and opaque
version IDs are unaffected. This was an SDK bug, not a MinIO encoding deviation.
Current Versity multipart-marker and version-continuation deviations have minimal
boto3/raw-response reproductions, separate from its passing baseline and tag APIs.
The preserved old MinIO matrix remains historical evidence.

ZEROS3's UploadPartCopy HTTP 200 empty semantic result remains a separately
unsupported extension. boto3 returns an empty CopyPartResult; native parsing fails.
Common CRUD/streaming/concurrency support is unaffected. No external fix is made.
No live AWS/account policy behavior is inferred from these local fixtures.
