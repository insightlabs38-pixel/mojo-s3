# Goal: Build a Production-Quality Native Mojo Object Storage SDK with S3 as the First Backend

Build a serious, production-oriented object-storage library written natively in Mojo, beginning with a complete S3-compatible backend.

This is intended to become a legitimate open-source systems project, not a demo, thin boto3 wrapper, benchmark toy, or ZEROS3-specific client.

The implementation should exploit Mojo where useful while maintaining strict interoperability with ordinary S3-compatible systems.

The central design goal is:

> Provide a compact, well-engineered, genuinely Mojo-native object-storage abstraction whose first complete backend is S3.

Continue implementation autonomously through the task dependency graph. Do not stop after merely scaffolding the project or implementing a trivial proof of concept. Progress as far as is technically justified, while keeping every major subsystem tested and maintainable.

---

# 1. Non-Negotiable Constraints

## 1.1 Native Mojo

The core client must be implemented natively in Mojo.

Do NOT use:

- CPython
- boto3
- botocore
- Python HTTP libraries
- Python cryptography libraries
- Python wrappers as the real implementation
- shelling out to AWS CLI, curl, rclone, etc. for normal client operations

External tools may be used only for:

- interoperability verification
- test orchestration when unavoidable
- generating comparison fixtures
- debugging
- benchmarking

They must not constitute the implementation.

Before implementing infrastructure that Mojo already provides, inspect the current Mojo package ecosystem and standard-library capabilities.

Prefer native facilities whenever they are sufficiently correct and stable.

---

# 2. Product Boundary

The project must NOT become a ZEROS3 SDK.

ZEROS3 is:

- a useful test backend
- a reference S3 implementation
- a compatibility target
- a potential future extension target

It is not the abstraction boundary.

The implementation must remain compatible with ordinary S3-compatible object stores and should avoid assuming any ZEROS3-specific behavior.

The architecture should conceptually remain:

```text
Application
    |
    v
Generic ObjectStore API
    |
    +-------------------+
    |                   |
    v                   v
 S3 backend        future backends
    |
    v
S3 protocol implementation
    |
    +-- endpoint/addressing
    +-- request serialization
    +-- response parsing
    +-- error translation
    +-- SigV4
    +-- multipart
    +-- presigning
    +-- retry policy
    |
    v
Native HTTP transport
    |
    v
Mojo networking / HTTP facilities
```

---

# 3. Repository Principles

Favor a compact, legible codebase.

Do not create dozens of tiny modules solely for architectural aesthetics.

At the same time, do not collapse unrelated protocol behavior into one enormous source file.

Use cohesive subsystem boundaries.

Likely conceptual areas include:

```text
src/
  object_store/
  s3/
    client
    config
    addressing
    requests
    responses
    errors
    sigv4
    xml
    multipart
    presign
  http/
  crypto/
  util/

tests/
  unit/
  fixtures/
  integration/
  compatibility/

examples/
docs/
```

This structure is illustrative rather than mandatory.

Adapt it to Mojo packaging conventions.

Prefer the smallest structure that cleanly expresses the architecture.

---

# 4. Generic Object Storage API

Define a small provider-neutral abstraction.

Do not expose AWS-specific concepts through the generic interface unless there is a compelling reason.

The baseline object-store API should eventually support semantic operations roughly equivalent to:

```text
get
get_range
put
delete
exists
head
list
```

Potential types include:

```text
ObjectStore
ObjectMetadata
ObjectInfo
ObjectRange
ListResult
PutOptions
GetOptions
ListOptions
ObjectStoreError
```

Avoid overengineering the initial interface with dozens of knobs.

The generic abstraction should make common operations easy while allowing backend-specific capabilities through explicitly separated APIs.

Do not distort S3 semantics merely to satisfy abstraction purity.

If an operation is genuinely backend-specific, keep it on the S3 client or expose it through an optional capability layer.

---

# 5. S3 Client Configuration

Support explicit client configuration.

Baseline configuration should include:

- endpoint
- region
- credentials
- HTTP/HTTPS
- addressing style
- timeouts where supported
- retry policy
- optional user agent
- optional session token
- TLS verification behavior where applicable

Support at least:

```text
AccessKeyId
SecretAccessKey
SessionToken? 
```

Credential support should initially prioritize:

1. explicitly supplied credentials
2. environment variables

Only later implement broader AWS credential discovery.

Do NOT spend early effort cloning the entire AWS SDK credential-provider ecosystem.

Potential later providers include:

- shared AWS credentials file
- shared config file
- ECS credentials
- EC2 IMDS
- web identity
- STS AssumeRole

These are explicitly lower priority than protocol correctness.

---

# 6. Endpoint and Addressing Semantics

Implement S3 endpoint handling carefully.

Support:

## Path-style

```text
https://endpoint/bucket/key
```

## Virtual-host style

```text
https://bucket.endpoint/key
```

Path-style should be implemented first because it is useful for local S3-compatible servers.

Eventually support automatic or configurable selection.

Correctly handle:

- arbitrary ports
- localhost
- IP endpoints
- HTTPS
- custom domains
- trailing slashes
- buckets with unusual but valid names
- object keys containing slashes
- spaces
- Unicode where Mojo permits
- percent characters
- plus signs
- reserved URL characters
- repeated slashes
- empty path components

Do not normalize object keys in a way that changes S3 semantics.

---

# 7. URI Encoding and Canonicalization

Treat URL encoding and SigV4 canonicalization as protocol-critical code.

Implement explicit helpers rather than relying blindly on generic URL encoders.

Correctly distinguish between:

- URI path encoding
- canonical URI encoding
- query encoding
- canonical query ordering
- request URL construction

Pay special attention to:

```text
/
%
+
space
?
#
&
=
Unicode
already-percent-encoded sequences
```

Add dedicated fixture-based tests for canonicalization.

Do not proceed to claim SigV4 correctness without these tests.

---

# 8. AWS Signature Version 4

Implement SigV4 as an independent, reusable subsystem.

Expected conceptual inputs:

```text
method
canonical URI
query parameters
headers
payload hash
timestamp
region
service
credentials
```

Expected outputs should make it possible to produce:

```text
Authorization
x-amz-date
x-amz-content-sha256
x-amz-security-token
```

Implement:

- SHA-256
- HMAC-SHA256
- hexadecimal encoding
- canonical request construction
- signed-header selection
- canonical-header normalization
- credential scope
- string-to-sign
- signing-key derivation
- authorization-header construction

Where native Mojo cryptographic primitives exist and are suitable, prefer them.

Do not implement custom cryptographic algorithms unless necessary.

The signing implementation must be deterministic and heavily tested.

Create known-answer fixtures.

Prefer fixtures from:

- AWS SigV4 documentation
- independently generated reference requests
- known SDK outputs

Test:

- GET
- PUT
- HEAD
- DELETE
- query parameters
- custom metadata headers
- session-token credentials
- empty payload
- non-empty payload
- unusual paths
- duplicate/normalized whitespace
- sorted headers
- signed-header ordering

SigV4 failures must be diagnosable.

When practical, expose internal canonical request and string-to-sign values in debug/test APIs without leaking secrets by default.

---

# 9. HTTP Transport

Build a small transport abstraction between the S3 client and native Mojo HTTP functionality.

Conceptually:

```text
HttpRequest
HttpResponse
HttpTransport
```

Support:

- method
- URL
- headers
- request body
- response status
- response headers
- response body

Later support streaming bodies without redesigning the entire API.

Do NOT write a custom TCP, TLS, HTTP/1.1, or HTTP/2 implementation unless Mojo lacks all practical alternatives.

Transport should eventually support:

- connection reuse
- keep-alive
- configurable timeout behavior
- request cancellation if Mojo supports it
- bounded buffering
- streaming
- robust handling of partial reads/writes

Keep S3 semantics outside the transport layer.

---

# 10. Core S3 Operations

Implement and fully test these operations first.

## PUT Object

Support:

- empty object
- binary object
- text object
- arbitrary object key
- content type
- custom metadata
- payload hash
- overwrite

Return useful result information where available:

- ETag
- version identifier where present

## GET Object

Support:

- ordinary full retrieval
- binary-safe contents
- metadata extraction
- content length
- ETag
- content type

## HEAD Object

Support:

- existence checks
- metadata
- content length
- ETag
- appropriate handling of missing objects

## DELETE Object

Support normal delete semantics.

Do not treat successful idempotent deletion incorrectly as an error.

## ListObjectsV2

Support at least:

- prefix
- delimiter
- max keys
- continuation token

Parse:

- object keys
- sizes
- ETags
- timestamps if practical
- prefixes
- truncation state
- next continuation token

Eventually provide an iterator/pagination helper.

---

# 11. XML

S3 heavily relies on XML.

Use an existing reliable Mojo XML facility if one exists and is appropriate.

Otherwise implement the smallest robust parser required for the supported S3 response structures.

Do NOT casually build a full standards-compliant general XML implementation unless absolutely necessary.

At minimum parse correctly:

- ListObjectsV2
- multipart initiation
- multipart completion
- S3 error responses

Handle:

- entities
- escaped values
- whitespace
- optional elements
- namespace variation where relevant

Add fixtures for known responses.

---

# 12. S3 Error Model

Do not expose raw status codes as the only error mechanism.

Parse S3 XML errors and preserve useful fields.

Potential model:

```text
S3Error:
    status
    code
    message
    request_id
    host_id
    resource
```

Map common cases into useful typed/generic errors where appropriate:

```text
NotFound
AccessDenied
InvalidRequest
InvalidRange
PreconditionFailed
SignatureMismatch
ExpiredRequest
Timeout
TransportFailure
ServerFailure
```

Retain enough original information for debugging.

Never silently convert server errors into empty values.

---

# 13. Range Requests

After baseline CRUD works, implement ranged GET.

Support:

```text
bytes=start-end
bytes=start-
```

If suffix ranges are reasonable to expose, support those too.

Test:

- first byte
- final byte
- middle range
- full-size range
- beyond-end range
- zero-length edge cases
- invalid range
- large object

Correctly interpret:

```text
206 Partial Content
Content-Range
Content-Length
```

---

# 14. Presigned URLs

Implement native SigV4 query-string signing.

Support at least:

- presigned GET
- presigned PUT

Configuration should include expiration.

Test:

- successful GET
- successful PUT
- expiration behavior where practical
- query tampering
- path tampering
- credential tampering
- signature tampering
- metadata/header constraints where applicable

Presigning should share canonicalization/signing primitives with ordinary SigV4 instead of duplicating them.

---

# 15. Streaming

Once buffered CRUD is stable, design streaming APIs.

Goals:

- avoid loading large objects fully into RAM
- allow streamed downloads
- allow streamed uploads
- preserve backpressure if Mojo primitives permit it
- make resource ownership explicit
- ensure streams close correctly on errors

Avoid introducing complex asynchronous abstractions merely for appearance.

Use the simplest model that is genuinely useful with Mojo's runtime.

Benchmark memory behavior against large objects.

---

# 16. Multipart Upload

Implement multipart after ordinary PUT is reliable.

Support:

```text
CreateMultipartUpload
UploadPart
CompleteMultipartUpload
AbortMultipartUpload
```

Potential convenience API:

```text
multipart_put(...)
```

Requirements:

- configurable part size
- minimum S3 part-size rules
- correct part numbering
- capture ETags
- ordered completion manifest
- cleanup/abort on failure when appropriate

Later support concurrent part upload.

Test:

- 1-part boundary behavior
- multiple parts
- uneven final part
- empty/near-empty objects
- aborted upload
- failed individual part
- reordered completion data
- retry behavior
- final content integrity

---

# 17. Concurrency

Only introduce concurrency after functional correctness exists.

Potential targets:

- concurrent multipart parts
- concurrent independent object operations
- parallel downloads

Concurrency design should be bounded.

Do not spawn unlimited work.

Make concurrency configurable.

Check for:

- race conditions
- shared-signing-state bugs
- connection pool correctness
- accidental buffer reuse
- cancellation/error propagation

---

# 18. Retry Policy

Implement retries centrally.

Distinguish retryable failures from permanent failures.

Potential retryable cases:

```text
408
429
500
502
503
504
transport interruption
connection reset
```

Consider S3-specific transient failures such as SlowDown.

Use exponential backoff with jitter where possible.

Honor Retry-After when sensible.

Avoid retrying:

- authentication failures
- malformed requests
- most client 4xx responses
- non-idempotent operations where retry safety is unclear

Expose retry configuration.

Add deterministic testing hooks so tests do not actually sleep for long periods.

---

# 19. Checksums and Data Integrity

After the fundamental protocol is working, investigate support for:

- Content-MD5 where appropriate
- SHA-256 payload validation
- newer S3 checksum headers if practical
- downloaded content-length validation

Do not incorrectly assume ETag always equals MD5.

Multipart ETags must not be interpreted as ordinary MD5 values.

---

# 20. Credential Providers

Use a provider abstraction so credential support can grow later.

Conceptually:

```text
CredentialsProvider
StaticCredentialsProvider
EnvironmentCredentialsProvider
```

Later:

```text
SharedCredentialsProvider
ProcessCredentialsProvider
ImdsCredentialsProvider
EcsCredentialsProvider
WebIdentityProvider
AssumeRoleProvider
```

But do not implement the later set before core S3 is stable.

Support session tokens from the beginning because temporary AWS credentials are common.

---

# 21. Time Handling

SigV4 depends on correct UTC time.

Implement a clean clock abstraction if doing so materially improves tests.

Allow deterministic signing tests using fixed timestamps.

Do not scatter calls to current time throughout signing code.

Potential shape:

```text
Clock
SystemClock
FixedClock
```

Avoid overengineering if Mojo already gives an easier deterministic mechanism.

---

# 22. Test Architecture

Testing quality is a first-class deliverable.

Create multiple levels.

## Unit Tests

Test:

- URI encoding
- canonical query generation
- canonical headers
- header whitespace normalization
- payload hashes
- HMAC
- SigV4 signing
- credential scope
- endpoint generation
- XML parsing
- error parsing
- range-header generation
- multipart helpers

## Fixture Tests

Maintain protocol fixtures for:

- canonical requests
- AWS signing examples
- XML responses
- S3 errors
- ListObjectsV2
- multipart responses

## Integration Tests

Use a real S3-compatible endpoint.

ZEROS3 should be one primary integration backend where available.

Use isolated buckets/prefixes per test run.

Clean up created objects.

## Contract Tests

Write one provider-neutral contract suite.

The same suite should be runnable against multiple providers.

The contract suite should ultimately cover:

- bucket access
- PUT
- GET
- HEAD
- DELETE
- overwrite
- LIST
- prefix behavior
- metadata
- zero-byte object
- binary data
- unusual keys
- large object
- ranges
- presigned GET
- presigned PUT
- multipart
- concurrency
- failure semantics

Avoid provider-specific assertions unless the S3 standard genuinely leaves behavior undefined.

---

# 23. ZEROS3 Integration

ZEROS3 is an especially useful compatibility backend.

Use it aggressively for testing because:

- it is locally controllable
- it implements S3 semantics
- it exercises SigV4
- it supports ranges
- it supports multipart
- it has strong external compatibility validation
- its underlying CAS/CDC implementation makes large object tests interesting

However:

DO NOT import internal ZEROS3 assumptions into the Mojo client.

Do NOT make the Mojo implementation depend on ZEROS3-specific APIs.

Do NOT implement CDC/CAS/Xet features in the baseline S3 layer.

ZEROS3-specific features can later be implemented as optional explicit extensions.

---

# 24. Compatibility Matrix

As the implementation matures, design the tests so they can run against:

1. ZEROS3
2. MinIO if available
3. another locally available S3-compatible server if useful
4. AWS S3 when credentials are explicitly available and usage is safe

Do not require paid AWS access for basic development.

Keep integration configuration environment-driven.

Example variables might resemble:

```text
S3_ENDPOINT
S3_REGION
S3_ACCESS_KEY
S3_SECRET_KEY
S3_SESSION_TOKEN
S3_TEST_BUCKET
S3_FORCE_PATH_STYLE
```

Do not hardcode credentials.

---

# 25. Interoperability Verification

Where useful, cross-check results using mature clients such as:

- AWS CLI
- rclone
- Go AWS SDK
- boto3

These are verification or fixture-generation tools only.

For example:

1. upload using Mojo
2. download with AWS CLI/rclone
3. compare bytes

Then reverse:

1. upload with conventional client
2. retrieve using Mojo
3. compare bytes

Use such tests to catch protocol mistakes that unit tests miss.

---

# 26. Performance

Correctness comes first, but performance matters.

Once the baseline works, benchmark:

- small PUT latency
- small GET latency
- large sequential upload throughput
- large sequential download throughput
- ranged reads
- multipart upload
- concurrent operations
- memory consumption
- connection reuse effects

Do not optimize against meaningless microbenchmarks while protocol operations remain incomplete.

Look specifically for avoidable copies.

Mojo may provide an advantage through:

- native buffers
- predictable memory ownership
- zero/low-copy parsing
- efficient hashing
- compiled loops

Use those capabilities where practical.

Do not compromise correctness to achieve benchmark numbers.

---

# 27. Allocation and Copying

Inspect data flow for unnecessary copies:

```text
user buffer
 -> request representation
 -> HTTP layer
 -> socket
```

and:

```text
socket
 -> HTTP response
 -> object buffer
 -> user
```

Where Mojo permits, minimize redundant allocations and transformations.

Do not make zero-copy architecture a blocker for v0.1.

Instrument or benchmark before performing complicated optimizations.

---

# 28. Large Object Handling

Eventually test with objects large enough to reveal:

- memory amplification
- buffering bugs
- integer overflow
- multipart errors
- stream truncation
- range mistakes
- connection instability

Avoid relying solely on tiny fixtures.

Use deterministic generated binary content and verify hashes after round trip.

---

# 29. Security

Treat credentials as secrets.

Requirements:

- never log secret keys
- never print full Authorization headers by default
- avoid exposing signing keys
- redact session tokens
- avoid placing credentials in URLs
- keep debugging output opt-in

Canonical-request debugging is acceptable if secret-bearing values are handled safely.

TLS verification should be enabled by default.

Any insecure option intended for local development must be explicit.

---

# 30. Robustness and Edge Cases

Systematically test:

### Object keys

```text
simple.txt
dir/file.txt
dir//file
space key
plus+key
percent%key
question?key
hash#key
ampersand&key
equals=key
Unicode key
very long key
```

### Object sizes

```text
0 B
1 B
small KB
several MB
multipart boundary
large multipart object
```

### Metadata

- none
- one field
- multiple fields
- mixed casing
- unusual but valid values

### Failures

- missing object
- wrong credentials
- wrong region if meaningful
- malformed endpoint
- server unavailable
- timeout
- invalid range
- expired presigned URL
- tampered signature
- interrupted upload

---

# 31. API Quality

The high-level API should be pleasant to use.

A simple use case should not require the caller to understand SigV4 internals.

Aim for something conceptually like:

```text
store = S3Store(config)

store.put("bucket", "hello.txt", data)
data = store.get("bucket", "hello.txt")
meta = store.head("bucket", "hello.txt")
items = store.list("bucket", prefix="logs/")
store.delete("bucket", "hello.txt")
```

Exact Mojo syntax should follow idiomatic language conventions.

Advanced users should still be able to access:

- custom headers
- request options
- presigning
- ranges
- multipart
- retry policy

Avoid an API made entirely of giant option structs for ordinary operations.

---

# 32. Examples

Add executable examples as features mature.

Examples should include:

1. configure a custom endpoint
2. upload an object
3. download an object
4. list objects
5. retrieve a byte range
6. generate a presigned URL
7. multipart upload
8. stream a large object

Examples must compile/run against the actual API.

Do not let documentation drift away from implementation.

---

# 33. Documentation

Maintain:

## README

Explain:

- what the project is
- why native Mojo object storage matters
- current supported features
- installation
- basic example
- compatibility status
- limitations
- roadmap

## Architecture document

Explain major components and why their boundaries exist.

## Compatibility document

Maintain a matrix such as:

```text
Feature              ZEROS3   MinIO   AWS
PUT
GET
HEAD
DELETE
LIST
Range
Presign
Multipart
Metadata
```

Only mark functionality supported after testing it.

## Development/status document

Maintain a concise current state:

```text
Completed
In progress
Known failures
Known limitations
Next tasks
```

This should be updated during the run so another agent or future session can resume without rediscovering the repository.

---

# 34. CI

If the repository environment supports CI, establish a useful pipeline.

At minimum:

- formatting
- compile/build
- unit tests
- fixture tests

Where feasible:

- launch local S3-compatible server
- run contract tests
- run integration tests

Avoid brittle CI that depends on external cloud credentials.

---

# 35. Formatting and Static Quality

Use the strongest stable Mojo tooling available for:

- formatting
- compilation checks
- package validation
- static diagnostics

Keep warnings clean where practical.

Do not suppress errors merely to achieve a green build.

---

# 36. Development Workflow

Work incrementally.

The desired rhythm is:

```text
inspect
design
implement
compile
test
fix
commit/checkpoint
continue
```

For each meaningful subsystem:

1. inspect existing code
2. understand dependencies
3. implement the smallest coherent increment
4. compile immediately
5. run relevant tests
6. fix failures
7. expand coverage
8. proceed

Do not implement five untested subsystems and debug everything at the end.

---

# 37. Mandatory Gates

Do not treat a subsystem as complete without passing its gate.

## Gate A — Repository health

- project builds
- package layout is coherent
- tests can run

## Gate B — Crypto/signing

- SHA/HMAC verified
- canonical request tests pass
- known SigV4 fixtures pass

## Gate C — Basic interoperability

Against a real S3-compatible server:

- PUT works
- GET returns identical bytes
- HEAD works
- DELETE works

## Gate D — Listing

- ListObjectsV2 parses correctly
- pagination works

## Gate E — Edge keys

Core operations work with unusual object keys.

## Gate F — Ranges

Range reads return correct byte slices.

## Gate G — Presigning

Presigned GET and PUT work externally.

## Gate H — Multipart

Large multipart upload round-trips correctly.

## Gate I — Concurrency/retry

Bounded concurrent operations and retry behavior pass stress tests.

Do not claim later-stage completion when earlier gates remain broken.

---

# 38. Anti-Goals

Do NOT spend substantial effort on:

- GUI
- web frontend
- object browser
- CLI polish before SDK maturity
- full AWS SDK parity
- every AWS service
- bucket policy management
- IAM administration
- S3 Control APIs
- Glacier workflows
- replication configuration
- lifecycle configuration
- event notifications
- obscure AWS-only APIs

The project is an object-storage client, not an AWS management SDK.

---

# 39. Future Extension Boundary

Design enough flexibility that future extensions are possible without polluting the base API.

Potential later work includes:

- additional object-store backends
- ZEROS3-specific capabilities
- CAS APIs
- CDC-aware transfers
- Xet-inspired operations
- xorbs
- delta transfer
- deduplicated upload
- content-addressed object references
- sync engine
- high-performance transfer manager

Do not implement these until the generic S3 implementation is mature.

If a capability system is helpful later, it might conceptually expose:

```text
supports_ranges
supports_multipart
supports_presign
supports_cas
supports_cdc
```

But do not create speculative abstractions with no current use.

---

# 40. Priority Order for This Run

Proceed approximately in this order, adapting only when repository reality requires it.

## Phase 0 — Inspect

- inspect repository
- inspect Mojo version/toolchain
- inspect available native HTTP APIs
- inspect crypto APIs
- inspect XML support
- inspect package/test conventions
- identify existing partial implementation

Record important findings.

## Phase 1 — Foundation

- package/repository structure
- configuration types
- credentials
- URL/addressing utilities
- HTTP request/response abstraction
- native transport baseline
- deterministic time handling where useful

## Phase 2 — SigV4

- SHA-256/HMAC integration
- canonical URI
- canonical query
- canonical headers
- payload hash
- signing key
- authorization
- fixtures
- exhaustive unit tests

Do not move past this casually.

## Phase 3 — CRUD vertical slice

Implement:

- PUT
- GET
- HEAD
- DELETE

Verify against ZEROS3 or another available S3 server.

Round-trip arbitrary binary content.

## Phase 4 — Listing and errors

- ListObjectsV2
- XML
- pagination
- structured S3 errors
- generic error mapping

## Phase 5 — ObjectStore abstraction

Once semantics are understood from real implementation, finalize the generic abstraction.

Avoid designing the generic interface entirely in advance of the backend.

## Phase 6 — Range support

- GET ranges
- response validation
- edge-case tests

## Phase 7 — Presigning

- presigned GET
- presigned PUT
- tampering tests
- expiry tests

## Phase 8 — Streaming

- streaming download
- streaming upload
- memory tests

## Phase 9 — Multipart

- initiate
- part upload
- complete
- abort
- helper
- tests

## Phase 10 — Production hardening

- retries
- bounded concurrency
- connection reuse
- timeouts
- checksums
- better diagnostics
- stress testing

## Phase 11 — Compatibility

Run the common contract suite against as many accessible S3-compatible implementations as practical.

## Phase 12 — Performance

Benchmark and optimize obvious hotspots only after correctness is demonstrated.

---

# 41. Autonomous Task Selection

This is a `/goal` run.

Do not repeatedly stop for permission on ordinary implementation choices.

Use engineering judgment and continue to the next logical task.

Only stop or explicitly flag an issue when:

- a required external dependency is unavailable
- Mojo fundamentally lacks a needed primitive
- API behavior cannot be determined safely
- credentials or destructive external actions would be required
- multiple architectural options have materially different irreversible consequences
- an unresolved compiler/runtime limitation blocks progress

Otherwise:

```text
find next highest-value unblocked task
implement it
verify it
continue
```

---

# 42. Decision Policy

When uncertain, prefer in this order:

1. protocol correctness
2. interoperability
3. testability
4. API clarity
5. maintainability
6. performance
7. feature count

Do not trade correctness for superficial completeness.

A smaller client that reliably interoperates with S3 is more valuable than a broad implementation containing unverified behavior.

---

# 43. Code Generation Discipline

Do not generate large speculative files merely to make apparent progress.

Every substantial implementation should be tied to:

- an immediate feature
- a known protocol requirement
- a test
- or an established architectural need

Avoid placeholder classes and future-oriented boilerplate.

Remove dead scaffolding when discovered.

---

# 44. Debugging Policy

When something fails:

1. reduce the failure
2. inspect actual request/response
3. compare against known-good implementation if useful
4. identify protocol discrepancy
5. add regression test
6. fix root cause

For SigV4 mismatches, compare:

```text
canonical request
canonical request hash
credential scope
string to sign
signed headers
signature
```

Do not randomly change encoding until the request happens to succeed.

---

# 45. Benchmarking Policy

Benchmarks must represent actual useful operations.

Measure at minimum where feasible:

```text
small GET latency
small PUT latency
large GET throughput
large PUT throughput
range throughput
multipart throughput
peak memory
```

Compare configurations only when equivalent in correctness.

Record enough environment information to make numbers meaningful.

Avoid marketing claims from unstable microbenchmarks.

---

# 46. Compatibility Philosophy

S3 compatibility is determined by actual behavior, not by compiling an API with S3-shaped method names.

A feature counts as implemented only when:

1. request serialization is correct
2. authentication is correct
3. response parsing is correct
4. error behavior is reasonable
5. tests pass against at least one real S3 implementation
6. edge cases have appropriate coverage

---

# 47. Expected Deliverable State

Continue as far as the available run allows.

A minimally strong result should leave the repository with:

- coherent Mojo package structure
- buildable native implementation
- documented architecture
- native HTTP transport
- robust SigV4
- fixture tests
- PUT
- GET
- HEAD
- DELETE
- ListObjectsV2
- parsed S3 errors
- provider-neutral contract tests
- successful local S3 integration
- README and examples

A stronger result additionally includes:

- unusual-key coverage
- ranged reads
- presigned URLs
- metadata
- pagination
- streaming
- multipart
- bounded concurrency
- retries
- connection reuse
- cross-provider compatibility tests
- initial benchmarks

An excellent run reaches production-hardening work while keeping earlier functionality tested and clean.

---

# 48. End-of-Run Requirements

Before concluding the run:

1. run all applicable tests
2. run formatter/static checks
3. ensure the project builds cleanly
4. rerun critical integration tests
5. inspect repository for temporary debugging artifacts
6. update README if behavior changed
7. update compatibility matrix
8. update implementation/status document
9. record known failures rather than hiding them
10. identify the next highest-value tasks

Produce a concise final summary containing:

```text
Implemented
Verified
Tests added
Compatibility confirmed
Performance observations
Known limitations
Unresolved blockers
Recommended next tasks
```

Do not call something complete merely because code exists.

---

# 49. Stretch Goals

Only pursue these after the main client is demonstrably solid.

Potential stretch work:

- virtual-host addressing
- richer credential provider chain
- concurrent multipart transfer manager
- resumable multipart support
- automatic multipart threshold selection
- download parallelization
- checksum negotiation
- request metrics
- tracing hooks
- connection-pool tuning
- benchmark suite
- fuzz/property tests for URI encoding
- fuzz/property tests for XML parsing
- differential SigV4 testing against AWS SDKs
- differential request construction against mature clients

Particularly valuable stretch work is differential testing: generate equivalent requests with the Mojo client and a mature SDK and compare canonicalization/signing behavior under many randomized but valid inputs.

---

# 50. Long-Term Quality Standard

Treat this repository as something that may eventually be used by other Mojo projects rather than as hackathon code.

The target qualities are:

- compact
- native
- dependable
- interoperable
- understandable
- well-tested
- easy to extend
- difficult to misuse

Do not maximize LOC.

Do not maximize the number of checked roadmap boxes.

Maximize the amount of verified, durable systems software produced during the run.