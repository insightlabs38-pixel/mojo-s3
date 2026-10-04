# Local benchmark observations

October 4, 2026, Linux x86-64 cloud workspace, Mojo 1.1.0 (8189361e), system
OpenSSL 3/libcurl/libxml2. Servers run on localhost and use the local filesystem.
These are single-run observations, not reproducible comparative performance claims.
No remote network, paid cloud service, or production workload was measured.

`examples/benchmark.mojo` performs ten small-object warmups, then 100 PUTs and
100 GETs, reporting mean latency. GET timing includes content verification. The
large fixture is 32 MiB with unique 64 KiB block identifiers. File upload timing
includes SHA256 pre-hashing; download timing includes staged writes, length checks,
fsync and rename. A 1 MiB range and sequential/four-worker multipart are measured.
Large contents are verified independently after roundtrips and cleaned up.

| Measurement | MinIO 2025-04-22 | ZEROS3 f391b7e |
|---|---:|---:|
| Small PUT mean, µs | 3058 | 2501 |
| Small GET mean, µs | 794 | 411 |
| Stream upload, MiB/s | 179 | 142 |
| Stream download, MiB/s | 644 | 334 |
| 1 MiB range, MiB/s | 172 | 219 |
| Sequential multipart, MiB/s | 176 | 79 |
| Four-worker multipart, MiB/s | 283 | 77 |

The operations reuse one client's connections. Multipart repeats the same file,
so cache/deduplication/filesystem behavior affects server work. Four workers helped
in this MinIO run but did not help ZEROS3. This is evidence for measuring each
backend rather than assuming concurrency improves throughput. No optimization or
marketing conclusion is drawn from these runs.

A separate compiled native streaming/integrity/failure-preservation test against
MinIO used 13,596 KiB peak RSS and took 0.398 seconds with the same 32 MiB fixture.
This supports bounded-memory file transfers. Buffered uploads still copy the
request payload; multipart submission has about two buffers per active part.
The worker count (1–16) and part size (5–64 MiB) bound that memory explicitly.

Reproduce with authorized local test configuration:

```sh
python scripts/generate_transfer_fixture.py /tmp/source.bin 32
export S3_STREAM_SOURCE=/tmp/source.bin
export S3_STREAM_DESTINATION=/tmp/download.bin
# Also set S3_ENDPOINT/S3_REGION/S3_ACCESS_KEY/S3_SECRET_KEY/S3_TEST_BUCKET.
scripts/build examples/benchmark.mojo build/benchmark
build/benchmark
```

For stronger conclusions, repeat trials, report distributions, separate backend
cache/deduplication states, measure connection reuse controls, and test realistic
remote latencies and object sizes. Those sustained performance studies are pending.
