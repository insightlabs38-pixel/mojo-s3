# Verified compatibility

Local tests on October 4, 2026 with synthetic local credentials. AWS credentials
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
| Negotiated full-object SHA256 checksums | Passed | Untested | Untested | Untested |

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

These current results use stable Mojo 1.1.0. The isolated TSan runtime evidence
uses the exact nightly and unchanged baseline specified in TSAN.md. These results do not qualify additional platforms or Versity checksum behavior.
