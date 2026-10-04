# Architecture

`objects.mojo` defines provider-neutral values and the `ObjectStore` trait. The
contract suite is generic over that trait. AWS authentication, presigning, and
multipart remain explicitly S3-specific APIs.

`client.mojo` coordinates addressing, signing, transport, status handling, retry,
and operation-specific response validation. `config.mojo` supplies explicit/env
credentials and the UTC clock. A fixed timestamp is available for deterministic
tests; production uses libc UTC conversion at one entry point.

`protocol.mojo` encodes UTF-8 bytes for S3 URI/query rules, preserves path
components, sorts encoded query pairs, and normalizes headers. Encoding a literal
`%2F` produces `%252F`; object keys are raw names, not pre-escaped paths. Duplicate
headers combine in wire order before their names are sorted.

`signing.mojo` receives deterministic protocol inputs and returns a canonical
request, string to sign, and authorization. It shares the same primitives with
query presigning. The low-level diagnostic fields can contain session tokens;
callers must redact them. The normal client never logs these values or credentials.

`http.mojo` represents requests/responses independently of S3. Its transport binds
libcurl directly, including Mojo C-ABI read/write callbacks; there is no C helper
or Python transport. It owns one easy handle, resets request options between
operations, and retains libcurl's connection cache. Global libcurl initialization
is retained for process lifetime; handles and header lists are released. Requests
never follow redirects. Content decoding is disabled to preserve stored bytes.
The buffered body ceiling is 64 MiB by default; response headers have a 64 KiB
ceiling. File transfers bypass body buffering and remain synchronous.

`files.mojo` owns Linux descriptors and temporary files. Uploads hash in 64 KiB
chunks before rewinding for libcurl. The explicit post-request use of the file in
`upload_file` keeps Mojo's early destructor scheduling from closing its descriptor
before libcurl runs. Downloads stage and commit only after a successful response
and matching byte count. Error XML in staged downloads is read back with a 64 KiB
ceiling. Sources must be stable, seekable files; no advisory locking is imposed.

`crypto.mojo` binds OpenSSL SHA256/HMAC; file hashing uses EVP contexts. No custom
crypto algorithm is implemented. `xml.mojo` uses a bounded libxml2 pull reader:
local names ignore namespace prefixes, predefined/numeric entities and CDATA are
handled, DTD/entity-reference nodes are rejected, network loading is disabled,
and document/depth/node-count limits apply. Element values are selected by parent
index, preventing unrelated nested elements from replacing required fields.

`errors.mojo` retains status, code, message, request/host IDs, resource, and generic
category. Public calls raise standard Mojo `Error` with a short non-secret
summary; structured details remain in `last_error`. Malformed error XML preserves
the HTTP error. A successful retry clears earlier error state.

`retry.mojo` holds pure policy decisions and capped full-jitter backoff. The client
re-signs each attempt, rewinds uploads/resets staged downloads, honors delta/date
Retry-After up to 60 seconds, and retries only safe operations on selected status
or transport failures. Multipart initiation/completion do not automatically replay.
Retries of versioned PUTs may produce multiple versions even though final object
content is unchanged. HTTP dates are parsed by libcurl; clock and parser inputs
are separated for deterministic tests. Cancellation is pending.

`multipart.mojo` implements the S3 capability without adding multipart to the
neutral trait. Completion validates/escapes/sorts part manifests and recognizes
XML errors even inside HTTP 200. The file helper processes one part at a time and
aborts on failure, preserving the primary error. Abort failure reports an orphan
UploadId rather than silently hiding required cleanup.

`concurrent.mojo` adds a Linux-only bounded multipart capability. Workers receive
fully initialized stable contexts, each with its own config copy, transport,
descriptor, and buffers. Part numbers use disjoint strides; results occupy
preallocated disjoint slots and are inspected only after pthread_join. A native
atomic stop flag prevents queued work after a failure. Every launched thread is
joined, including partial launch failure, before abort or context destruction.
Thread entry catches exceptions before returning across the C ABI. An impossible
join-invariant failure aborts the process rather than freeing live contexts.
The internal launch-failure hook is used only by deterministic tests.

Full-object checksum support uses OpenSSL EVP Base64 and SHA256. S3-specific
negotiation is opt-in through config; returned full SHA256 checksums are verified.
Generic metadata distinguishes a supplied checksum from verified integrity.
Composite checksums and partial-range responses cannot be verified with a
whole-object digest, so they retain `checksum_verified=False`. Streamed validation
hashes the staged file before rename. CRC/MD5 and composite validation are pending.

## Toolchain/ecosystem inspection

The installed compiler is Mojo 1.1.0 (8189361e). The available current upstream
stdlib was inspected at Modular commit 24f4ceb2ff1701aaca81dc974b7b4794d7d2a0a5.
It offers FFI, files, collections, environment and time facilities, but no usable
HTTP/TLS, cryptographic, XML, or standalone public thread-pool API was found.
The public parallelize API requires MAX, which is not part of this compiler
installation. Native pthread C callbacks and std.atomic were subsequently
qualified with allocations, caught errors, OpenSSL calls, and real S3 multipart
work. No MAX or Python runtime dependency was added. Actual
bindings and lifetime behavior were compiled and tested with 1.1.0, rather than
assuming upstream source matched the installed release.

The initial platform is Linux x86-64 with OpenSSL 3, libcurl (>= 7.84 recommended
for thread-safe global initialization), and libxml2. File flags, errno access,
and opaque libc tm storage are Linux-specific. Porting requires reviewing those
ABI assumptions and rerunning the full suite. No ZEROS3 internals or CAS/CDC
behavior enter the client.
