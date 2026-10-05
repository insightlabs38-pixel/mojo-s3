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
request payload; historical multipart submission used part-sized buffers. The convergence file
path now streams bounded 64 KiB chunks, independently of 5 MiB–5 GiB part size.

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

## October 5 phase-2 local samples

Mojo1.1.0, Linux6.18.44 x86-64/glibc2.41, MinIO2025-04-22 on loopback,
32MiB position-sensitive file, 5MiB parts/ranges. Three samples per operation;
medians below. RSS uses Linux wait4 per-process ru_maxrss. Wall time includes
process startup and upload cleanup. Warm local page cache and concurrent compiler
load make these diagnostic samples, not cloud-throughput or fastest claims.

| Operation | Workers | Median seconds | Median RSS KiB |
|---|---:|---:|---:|
| stream | 1 | 0.0555 | 51416 |
| download | 1 | 0.0909 | 51416 |
| download | 2 | 0.0800 | 51416 |
| download | 4 | 0.0856 | 51416 |
| download | 8 | 0.1114 | 51496 |
| multipart | 1 | 0.1946 | 51416 |
| upload | 1 | 0.1849 | 51416 |
| upload | 2 | 0.2044 | 51416 |
| upload | 4 | 0.2005 | 54672 |
| upload | 8 | 0.2309 | 79664 |
| sha256 | 1 | 0.0625 | 51416 |
| sha1 | 1 | 0.0348 | 51416 |
| crc32 | 1 | 0.4366 | 51416 |
| crc32c | 1 | 0.3431 | 51416 |

Credential refresh network timing is fixture-only and backend/timeouts dominate;
no AWS latency estimate is made. CRC bitwise implementations are intentionally
simple and materially slower here; optimization should follow actual application
profiles and retain independent checksum oracles.

## October 5 convergence measurements

Three local samples per cell, same 32 MiB fixture, 5 MiB parts, Mojo 1.1.0 and pinned MinIO over loopback. Timing includes process startup, operation and upload cleanup; unrelated compilation and warm filesystem caches affect results. Current RSS samples poll /proc after executable selection at 2 ms intervals; short peaks may be missed. Historical wait4 results include inherited Python parent high-water marks and must not be treated as an exact RSS delta.

| Operation | Workers | Median seconds | Maximum sampled native RSS, KiB |
|---|---:|---:|---:|
| stream | 1 | 0.0611 | 13432 |
| download | 1 | 0.1461 | 30580 |
| download | 2 | 0.1155 | 43892 |
| download | 4 | 0.0757 | 50984 |
| download | 8 | 0.0806 | 58284 |
| multipart | 1 | 0.2717 | 14192 |
| download-progress | 1 | 0.1388 | 30492 |
| download-progress | 2 | 0.1340 | 43468 |
| download-progress | 4 | 0.0833 | 53368 |
| download-progress | 8 | 0.0895 | 71704 |
| upload-progress | 1 | 0.2136 | 14072 |
| upload-progress | 2 | 0.1587 | 14592 |
| upload-progress | 4 | 0.1243 | 14984 |
| upload-progress | 8 | 0.1110 | 15492 |
| stream-upload | 1 | 0.1579 | 13836 |
| stream-upload-checksum | 1 | 0.1791 | 13544 |
| upload | 1 | 0.1752 | 14420 |
| upload | 2 | 0.1170 | 14640 |
| upload | 4 | 0.1139 | 14600 |
| upload | 8 | 0.1085 | 15480 |
| sha256 | 1 | 0.0368 | 13052 |
| sha1 | 1 | 0.0356 | 13028 |
| crc32 | 1 | 0.4886 | 12752 |
| crc32c | 1 | 0.4241 | 13040 |

Progress cells use a coordinator observer; disabled cells use NoProgress. Stream-upload-checksum negotiates an actual full-object checksum. Multipart checksum negotiation is not implemented, so no enabled-multipart-checksum performance claim is made. Digest rows measure the hash only. Large planning is covered without allocating payloads; no full-capacity service throughput is claimed.

A separate independently verified wide wire test streamed 5,368,709,127 bytes (one 5 GiB part plus 7-byte tail), with 13,812 KiB sampled peak native RSS and 9.139 seconds elapsed. This is a sparse-file loopback correctness/memory control, not AWS upload performance.
