# Implementation checkpoint — October 4, 2026

## Completed and verified

Native Mojo 1.1.0 object-store/S3 package with explicit/env/session credentials,
UTC/fixed signing time, precise encoding/SigV4/query presigning, libcurl transport,
TLS/custom CA/timeouts/reuse/buffer bounds, libxml2 parsing, structured errors,
binary CRUD/metadata, listing/pagination, ranges, file streaming/atomic downloads,
multipart lifecycle and file helpers, retries with jitter/delta/date Retry-After,
bounded native pthread multipart, and full-object SHA256 checksum support.

Gates A–D and F–H pass locally. Gate E now passes repeated-slash, dot-path and
newline cases on ZEROS3; NUL-key LIST remains a documented backend limitation.
Gate I has live 1/2/4/8-worker multipart, deterministic failure/cleanup tests and
AddressSanitizer evidence, but dynamic ThreadSanitizer qualification is blocked by
an allocator/TSan incompatibility reproduced on the host and two clean userspaces. Production qualification is
not complete.

## Evidence

- Package precompile, compiled-package consumer, all example builds and formatting.
- SHA256 empty/abc/million-byte vectors and RFC 4231 HMAC short/long-key vectors.
- AWS published SigV4 fixture and 64 botocore canonical/signature comparisons.
- 2,000 deterministic URI/query/XML properties, adversarial percent/UTF8/XML
  checks, structured errors, range/header/endpoint/overflow/multipart fixtures.
- Fault fixtures for retries/reset recovery, TLS/default/custom trust, timeouts,
  redirects, connection reuse, HTTP 200 XML errors, bounds and corrupt checksums.
- Native common contracts on MinIO, Versity POSIX, and ZEROS3; 32 MiB file streaming,
  sequential multipart, and native concurrent multipart on all three.
- Part failure preserves the S3 error; queued work stops; workers join before abort;
  completion failure and partial pthread launch clean up correctly.
- AddressSanitizer passes both fault cleanup and real 1/2/4/8-worker uploads.
- MinIO local STS temporary credentials pass native CRUD/presign and concurrency.
- ZEROS3 virtual-host HTTP and verified HTTPS pass, including concurrent multipart
  and custom-CA propagation to workers.
- Negotiated full-object SHA256 validation passes on MinIO for buffered/streamed
  transfers. Composite checksums remain explicitly unverified in metadata.
- boto3↔Mojo bidirectional large transfers pass on MinIO and ZEROS3.

The 32 MiB fixture has unique 64 KiB block identifiers, so reordering full parts or
reusing the wrong buffer changes the final hash. Test buckets and incomplete
uploads are checked for cleanup. Native executables do not depend on CPython.
CI includes pinned local MinIO and ZEROS3, sessions, TLS and ASan; it has been
written and locally checked but not executed on hosted GitHub Actions.

## Runtime qualification blocker

`mojo build --sanitize thread` compiles, but the minimal program aborts before
main in tcmalloc initialization. Focused tracing proves that TSan clears a tagged
address hint, then MAP_FIXED_NOREPLACE reaches the kernel at address zero and
returns EPERM. Unlimited address-space limits, execution outside the sandbox,
a working C/TSan race detector control, and clean Ubuntu 24.04/Debian 12 userspace
reproductions rule out the original resource-limit guesses. Mojo 1.0.0 also fails.
The allocator startup hook cannot repair shared-library constructor ordering.

The strict `scripts/check-tsan` gate and manually dispatched workflow preserve
execution evidence and will run native concurrency suites once the runtime works.
See [TSAN.md](TSAN.md) for exact versions, tracing, repair attempts, and limits.
Production source remains frozen per the runtime-fix instructions. No available
unmodified runtime passed the minimal gate; no checks were suppressed. The
remaining original goal therefore cannot be called complete.

## Remaining limitations and next tasks

1. Resolve/qualify Mojo ThreadSanitizer and run the native concurrency suites.
2. Run against a safely authorized AWS test bucket; no AWS identity is attached.
3. Verify future backend fixes for NUL-key encoded listings and add broader
   provider/virtual-host combinations.
4. Add cancellation, generalized concurrent downloads/object batches, suffix
   ranges, pagination convenience, the requested credential-provider abstraction and refreshable providers,
   CRC/MD5/composite checksums, sustained stress/fuzzing, and portability.

Linux x86-64 is the current target. Each store/transport remains single-owner;
the concurrent helper creates one store per worker. Sources must remain stable.
Buffered requests copy payloads; concurrent multipart uses about two part buffers
per active worker. Errors raise Mojo Error with structured details in last_error.
Benchmark results and limits are in BENCHMARKS.md. Do not interpret ETag as MD5.

## Resume in this workspace

Repository `/workspace/mojo-s3`; compiler `/workspace/mojo-toolchain/bin/mojo`;
optional verification Python `/workspace/mojo-verification/bin/python` (boto3).
Native dependencies: libcrypto.so.3, libcurl.so.4, libxml2.so.2. Go 1.27.0 at
`/workspace/go127/go/bin/go` builds the pinned ZEROS3 fixture.

Local reference servers: MinIO :19001, Versity :19000, ZEROS3 :19003. Binaries/data
are outside the SDK repository; all use synthetic local-only keys and `mojo-test`.
Use DEVELOPMENT.md commands. Never reuse local dummy keys for remote endpoints.
The original user objective remains verbatim in GOAL.md.
