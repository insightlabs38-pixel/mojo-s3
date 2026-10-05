# Changelog

## 0.1.0-dev — unreleased

- Experimental bounded ListObjectVersions pages/paginator with separate delete
  markers, opaque IDs, strict encoding and marker-cycle rejection.
- Fix encoded listing spaces/literal plus to match S3 reference URL decoding.
- Deterministic concurrent-failure fixture rendezvous; current backend
  requalification, API freeze and release/distribution decisions documented.

Initial public source-distribution preparation. This is not a qualified release
candidate and no tag or upstream publication has been created.

- Native S3 CRUD, metadata, listing, ranges, SigV4/presigning, retries, TLS,
  file streaming, multipart and bounded native concurrent multipart baseline.
- Source installation with an installed build helper that discovers native
  libraries, plus a self-contained source archive and clean-consumer checks.
- Explicit API stability/ownership policy and adoption-focused documentation.
- Native static/environment/shared AWS profile credential providers, session
  tokens and regional AWS endpoint defaults, with fail-closed provider precedence.
- Suffix ranges and bounded page-at-a-time listing convenience.
- Experimental file transfer manager with automatic multipart selection and
  explicit worker/part-buffer bounds.

- Typed CopyObject/DeleteObjects/HeadBucket, common conditions/opaque versions,
  metadata/tags/storage/encryption options and structured region diagnostics.
- Native experimental Web Identity/container/IMDSv2 with expiration-aware refresh.
- Full-object SHA256/SHA1/CRC32/CRC32C; composite/unsupported integrity states.
- Bounded atomic concurrent downloads, coordinator progress and multipart cancellation.
- Explicit existing-bucket AWS harness and deterministic source-release dry run.
- 64-bit dynamic multipart planning, streamed 5 MiB–5 GiB file parts and bounded
  download scheduling with one owned outcome slot per worker.
- Experimental server-side multipart copy, explicit tag-copy policy, multipart
  inspection pagination and version-aware object-tag operations.
- Experimental signed ordinary AssumeRole with source refresh and rejected chaining.
- Coordinator cancellation without raw control pointers; wide-offset wire and
  malformed multipart/copy/tag fault oracles.

See STATUS.md and RELEASE_READINESS.md under docs for verification and pending
qualification. TSan remains strictly gated on a usable upstream runtime.
