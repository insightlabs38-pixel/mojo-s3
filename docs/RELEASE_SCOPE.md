# Initial S3 SDK completeness boundary

The first serious release is a native Mojo S3 data-plane library with a small
provider-neutral object contract. It is not an AWS administration SDK. New APIs
remain experimental until their ownership, errors and backend behavior are tested.

## Release-critical data plane

CRUD/metadata, bounded listing/pagination, closed/open/suffix ranges, presigning,
streamed file transfers, multipart and bounded concurrent transfers; usable
credential chain and endpoint resolution; bounded retries and explicit integrity;
common conditional reads/writes, CopyObject, bounded DeleteObjects, version IDs,
and common storage/encryption/request options; verified installation/distribution.
Actual AWS qualification is required before claiming AWS compatibility, and must
use an explicitly authorized existing bucket with randomized prefixes and cleanup.
No AWS identity is required for ordinary local-backend CI.

## Near-term SDK

Refreshable workload identity with explicit expiration/ownership/trust semantics;
concurrent ranged downloads with atomicity, progress/cancellation, richer checksum
algorithms and supported platform/compiler qualification. Keep robust lower-level
multipart/range APIs available alongside the optional manager. Generic source/sink
interfaces need a simple ownership design rather than a new I/O framework.

## Future administration

Bucket lifecycle, replication, Object Lambda, S3 Tables, IAM management, exhaustive
bucket-management APIs and async parity are not initial release blockers. Minimal
HeadBucket diagnostics are useful; bucket deletion/account-wide mutations do not
belong in qualification harnesses.

## Current evidence

Release-readiness commit `44faa2af60d0e5f476bbc6138794a87b852bb8df` passed hosted
[CI run 37248323851](https://github.com/insightlabs38-pixel/mojo-s3/actions/runs/37248323851).
This includes ordinary/examples, source install, MinIO, ZEROS3 and ASan. Phase 2
works on a separate branch; no merge, tag, package or release publication is authorized.
