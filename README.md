# mojo-s3

A native S3/object-storage SDK for Mojo. Compiled Mojo calls libcurl, OpenSSL and
libxml2 directly; SDK operations do not require CPython, boto3, MAX or subprocesses.
Use it for object data, datasets and application artifacts through a small
provider-neutral `ObjectStore` contract and an S3 backend.

**0.1.0-dev is unreleased development software, not a release candidate.** The
qualified baseline is Linux x86-64 with Mojo 1.1.0. Other platforms and compiler
released versions are unqualified; an exact nightly is qualified only in an isolated experiment. [API and version policy](docs/API.md).

## Install and build an application

Install Mojo 1.1.0 from its official distribution and the native dependencies:

```sh
sudo apt-get install libcurl4-openssl-dev libssl-dev libxml2-dev openssl
git clone --branch sdk/s3-phase2 https://github.com/insightlabs38-pixel/mojo-s3.git
cd mojo-s3
scripts/install --prefix "$HOME/.local"
```

Installation places Mojo source under `PREFIX/include/mojo` and a build helper
at `PREFIX/bin/mojo-s3-build`. From your application directory, build with:

```sh
"$HOME/.local/bin/mojo-s3-build" main.mojo build/app
./build/app
```

The helper supplies the import path and native linker libraries. `MOJO` selects a
compiler; `CRYPTO_LIBRARY`, `CURL_LIBRARY`, and `XML_LIBRARY` override native DSO
paths. Deployment still requires compatible native libraries.
`scripts/package` creates a source archive with release metadata, examples and
checks. Installed source is rebuilt with your consuming compiler; no precompiled
`.mojoc` is distributed. [Dependencies and platform status](docs/DEPENDENCIES.md).
Python can provide compiler/formatter tooling and test orchestration; built SDK
client operations have no CPython dependency.

## Upload and download

Save this as `main.mojo`. Configure an existing bucket where writes are authorized.

```mojo
from std.os import getenv
from mojo_s3.client import S3Store
from mojo_s3.config import S3Config
from mojo_s3.crypto import bytes_of


def main() raises:
    var store = S3Store(S3Config.from_env())
    var bucket = getenv("S3_TEST_BUCKET", "mojo-test")
    _ = store.put(bucket, "hello.txt", bytes_of("hello from native Mojo"))
    var result = store.get(bucket, "hello.txt")
    print("Downloaded bytes:", len(result.data))
    var metadata = store.head(bucket, "hello.txt")
    var page = store.list(bucket)
    store.delete(bucket, "hello.txt")
```

```sh
export S3_ENDPOINT=http://127.0.0.1:9000
export S3_REGION=us-east-1
export S3_ACCESS_KEY=your-test-access-key
export S3_SECRET_KEY=your-test-secret-key
export S3_TEST_BUCKET=your-isolated-test-bucket
```

Use HTTPS for remote endpoints. Credentials can include a session token; see
[credentials](docs/CREDENTIALS.md) for current provider behavior. Construct
`S3Config(endpoint, region, Credentials(access_key, secret_key, session_token))`
for explicit configuration. [Configuration and custom CA](docs/CONFIGURATION.md).

## Capabilities and verified compatibility

Implemented capabilities include binary CRUD and metadata, ListObjectsV2 pages, bounded pagination
and delimiter prefixes, inclusive closed/open-ended and suffix ranges, SigV4 and presigned
GET/PUT, streamed file transfers, multipart uploads, bounded native concurrent
multipart and ranged downloads, retries, connection reuse, verified TLS/custom CA,
SHA256/SHA1/CRC32/CRC32C full-object integrity, typed conditions/version IDs, copy,
batch deletion, and object encryption/storage options. Experimental native Web
Identity/container/IMDSv2 providers refresh expiring credentials. Calls raise standard Mojo `Error` with request-associated
`S3Error` detail in `store.last_error`.

The [compatibility matrix](docs/COMPATIBILITY.md) records actual tests against
MinIO, Versity Gateway and ZEROS3, including backend limitations. AWS S3 remains
untested. Signing fixtures match AWS published examples and botocore comparisons;
these do not replace live AWS qualification.

File transfers and multipart are described in [TRANSFERS.md](docs/TRANSFERS.md).
Each store/transport has one active owner; concurrent helpers create independent
worker stores. Low-level multipart, concurrent helpers and transport customization
are experimental. TSan compilation works, but Mojo's released runtime fails
before user main due to an independently reproduced allocator/runtime problem.
The [strict gate](docs/TSAN.md) stays in place. A separate isolated nightly runtime
experiment passes its prerequisites and the unchanged SDK gate; this does not
qualify the released runtime or install that experimental runtime for users.

`TransferManager` selects streamed or multipart file upload using a configured
threshold, worker count and part-buffer budget, and provides atomic streamed or
concurrent ranged downloads. Experimental coordinating-thread progress/cancellation
joins every worker and aborts uncommitted multipart uploads. Composite checksum
combination and resumable state remain pending. [Phase-2 semantics](docs/PHASE2.md). Do not treat ETags as content hashes.

## Development and further reading

Run `scripts/check` for ordinary credential-free checks. Real backend tests use an
existing isolated bucket and random prefixes; see [development](docs/DEVELOPMENT.md)
and [contributing](CONTRIBUTING.md). Executable [basic](examples/basic.mojo) and
[advanced](examples/advanced.mojo) examples show existing APIs.

[API](docs/API.md) · [Credentials](docs/CREDENTIALS.md) ·
[Configuration](docs/CONFIGURATION.md) · [Transfers](docs/TRANSFERS.md) ·
[Security](docs/SECURITY.md) · [Architecture](docs/ARCHITECTURE.md) ·
[Benchmarks](docs/BENCHMARKS.md) · [Roadmap](docs/ROADMAP.md) ·
[Current status](docs/STATUS.md)

Source installation and registry evaluation: [INSTALLATION.md](docs/INSTALLATION.md).
Current qualification and remaining release work: [RELEASE_READINESS.md](docs/RELEASE_READINESS.md).

Current large-object, lifecycle, role-provider and sanitizer evidence: [convergence checkpoint](docs/CONVERGENCE.md). New APIs remain experimental; no release has been published.

Final feature freeze and current-backend release limits: [RC convergence](docs/RC_CONVERGENCE.md). Version remains `0.1.0-dev`; live AWS qualification is the next release gate.
