# Explicit AWS qualification

**Not executed against AWS.** Ordinary CI needs no AWS credentials. The harness
compiles on Mojo 1.1.0 and refuses missing authorization before network access.
Use an existing dedicated **unversioned** test bucket, with permission to put/get/
head/list/delete and multipart uploads only inside its test prefix. No bucket is
created/deleted, no versioning/lifecycle/IAM/account setting is changed.

```sh
export AWS_PROFILE=your-test-profile AWS_REGION=your-bucket-region
export RUN_AWS_S3_INTEGRATION=1
export S3_AWS_TEST_BUCKET=your-existing-test-bucket
export S3_AWS_TEST_AUTHORIZATION="$S3_AWS_TEST_BUCKET"
# AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY / AWS_SESSION_TOKEN also work.
unset S3_ENDPOINT S3_FORCE_PATH_STYLE
scripts/check-aws
```

The runner generates `mojo-s3-qualification/<128-bit-random>/`, prints that exact
prefix, and uses native regional HTTPS virtual hosting. All keys stay under it;
cleanup deletes known test objects only. If permissions/network failure prevent
cleanup, inspect that printed prefix and outstanding multipart uploads manually.
Versioned buckets retain historical versions/markers, so they require owner-side
cleanup and are unsuitable for this ordinary harness. Session credentials are
exercised when supplied, with no token output. Web Identity/IMDS/provider refresh
has deterministic fixture coverage, not AWS workload-account coverage.

Tests include HeadBucket, copy and batch deletion, CRUD, metadata/content-type, listing/pagination, unusual/reserved/
Unicode keys, closed/open/suffix ranges, presigned GET/PUT, streamed file transfers,
sequential and concurrent multipart, TransferManager selection/concurrent download,
and four full-object checksum algorithms. KMS/DSSE, version administration and
cross-account authorization are separate future authorized gates.
