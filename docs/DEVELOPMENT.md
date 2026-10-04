# Development and verification

Run `scripts/format`, then `scripts/check`. The latter checks formatting,
precompiles the package, builds/runs unit and deterministic fixture suites, tests
an isolated local failure server and ephemeral TLS server, and builds every
example. Its native test binaries do not need Python to perform client operations.
Python fixtures are orchestration only. No signing fixture regeneration dependency
is required to run checked-in fixtures.

For local interoperability, start an S3-compatible server and provision an isolated
bucket. Set `S3_ENDPOINT`, `S3_REGION`, `S3_ACCESS_KEY`, `S3_SECRET_KEY`, and
`S3_TEST_BUCKET`, then run:

```sh
RUN_S3_INTEGRATION=1 scripts/check
# For streaming/multipart, additionally set S3_STREAM_SOURCE/S3_STREAM_DESTINATION.
scripts/build tests/test_interop.mojo build/test_interop
python scripts/interop.py "$PWD/build/test_interop" # optional boto3 verification
python scripts/stress.py "$PWD/build/test_integration" # 4 concurrent processes
```

The live integration suite uses random run IDs, cleans created objects, and uses
opaque continuation tokens unchanged. Extended-key failures encountered while
qualifying a backend must be documented, not removed from the record. The generic
contract intentionally tests names supported by both current reference servers;
transport and signer fixtures cover preserved unusual paths beyond their limits.

`generate_signing_fixtures.py` uses botocore 1.43.108 and seed 74391 with synthetic
credentials. It writes human-readable JSON reference data and executable Mojo
fixture assertions. After regenerating, run `scripts/format` and all signing
checks. botocore is an independent test oracle, never imported by SDK modules.

CI uses pinned Mojo, MinIO, and ZEROS3, ephemeral local credentials, and the same checks.
It has been authored here but has not run in GitHub Actions. CI includes local
native contracts, streaming/multipart, native workers, bidirectional interoperability,
sessions, virtual-host TLS and ASan without paid cloud access.

For resumable work, see STATUS.md and the original GOAL.md. Keep capabilities
marked untested until actual live-server validation. Do not interpret ETag as MD5;
for example multipart ETags are opaque values. Never print real credentials,
Authorization, session tokens, canonical requests containing tokens, or presigned
URLs in test/debug logs.

## Additional qualification

Generate a position-sensitive streaming fixture with
`scripts/generate_transfer_fixture.py /tmp/source.bin 32`. Each block has a unique
identifier so multipart order and buffer-reuse bugs change its digest.

`scripts/check` now includes thread/atomic smoke tests, 2,000 properties, checksum
faults and multipart failure/cleanup fixtures. With streaming paths configured,
`RUN_S3_INTEGRATION=1` also runs native multipart at 1/2/4/8 workers.
Use `RUN_EXTENDED_KEYS=1` on a backend known to preserve those key forms, and
`RUN_S3_CHECKSUMS=1` to require returned full-object SHA256 verification (MinIO
currently qualified). Unknown/unsupported checksums are not treated as verified.

Optional independent local MinIO session credential checks:

```sh
python scripts/session_credentials.py "$PWD/build/test_integration" "$PWD/build/test_concurrent_integration"
```

This helper refuses non-local STS endpoints. It is test orchestration, not a
runtime credential provider, and does not print session credential values.

For ZEROS3, build the pinned commit in COMPATIBILITY.md with Go 1.27.0. Provision a
local test bucket, run the common tests plus test_extended_keys, then:

```sh
scripts/build tests/test_vhost_tls.mojo build/test_vhost_tls
python scripts/run_vhost_tls.py /path/to/zeros3 "$PWD/build/test_vhost_tls"
scripts/build tests/test_concurrent_failures.mojo build/test_concurrent_asan --sanitize address
python scripts/run_fault_tests.py "$PWD/build/test_concurrent_asan"
```

The TLS harness owns its ephemeral server/certificates/data and cleans them on
exit. Native libcurl still verifies both CA and hostnames.
ThreadSanitizer was attempted and fails independently in Mojo's allocator; see
STATUS.md. ASan results are not a replacement for race qualification.
The native `examples/benchmark.mojo` records actual object operations and validates
large transfer hashes. See BENCHMARKS.md for conditions and observations.

## ThreadSanitizer runtime prerequisite

Run `RUN_TSAN_TRACE=1 scripts/check-tsan`. It preserves baseline execution, limits,
ELF dependencies and mmap evidence under ignored `build/sanitizers/`, and fails
before testing SDK concurrency if the minimal runtime fails. With a working
runtime, enable `RUN_S3_INTEGRATION=1` and the existing bucket/unique-block source
environment for real concurrent transfers. See [TSAN.md](TSAN.md); this gate is
currently blocked on all tested userspaces, with no suppressions.
