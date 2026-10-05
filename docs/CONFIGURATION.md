# Configuration

Construct `S3Config(endpoint, region, credentials, ...)` with explicit values, or
use `S3Config.from_env()`. Configuration is copied into a store. Configure retries
and integrity before creating the store; native transport options are separate.

| Setting | Default | Meaning |
|---|---|---|
| `endpoint` | Explicit constructor argument | HTTP/HTTPS S3 endpoint; custom ports supported |
| `region` | Explicit constructor argument | SigV4 signing region, independent of endpoint |
| `credentials` | Explicit constructor argument | Access key, secret key and optional session token |
| `virtual_host` | `False` | Prepend bucket to endpoint hostname instead of bucket in path |
| `fixed_timestamp` | Empty | System UTC clock; nonempty value is for deterministic tests |
| `max_attempts` | 3 | Total attempts, including the first; 1–10 |
| `retry_base_ms` | 100 | Full-jitter base delay, 0–60000 ms |
| `request_checksums` | `False` | Negotiate SHA-256 for ordinary object upload/download |

`from_env()` resolves environment credentials; `from_default()` additionally
reads AWS shared credentials/config profiles. Region precedence is `S3_REGION`,
`AWS_REGION`, `AWS_DEFAULT_REGION`, profile region (`from_default()` only), then
`us-east-1`. Generated endpoints are regional AWS HTTPS endpoints and use virtual
hosts. `S3Config.aws(credentials, region)` supplies the same defaults. `cn-*`
regions use the China partition suffix; other special AWS endpoints must be explicit.

`S3_ENDPOINT` supplies a custom endpoint and defaults to path style. Its signing
region remains independent of AWS endpoint validation. `S3_FORCE_PATH_STYLE` must
be `true` or `false` to override addressing. This changes the earlier environment
factory's global-endpoint/path-style AWS default; explicit constructor settings
remain compatible. See [credentials](CREDENTIALS.md) for precedence and limits.
Timeouts and checksum negotiation are not read from environment variables.

AWS interoperability remains untested. Redirects are disabled; region mismatch
and redirects are reported rather than forwarding signed credentials automatically.

## Addressing and TLS

Path-style is the default and suits localhost/IP endpoints. Virtual-host mode
requires bucket-aware DNS and a certificate covering the resulting hostname.
Dotted buckets may not match a wildcard certificate. Do not assume virtual-host
mode falls back automatically for IP endpoints or incompatible bucket names.
Custom virtual-host HTTP/HTTPS was exercised against ZEROS3; the compatibility
matrix records the tested scope. Use TLS verification and an explicit CA bundle
for a private certificate authority.

```mojo
from mojo_s3.http import CurlTransport

# Inside a raising function, with config already constructed:
var transport = CurlTransport(
    timeout_ms=30000,
    connect_timeout_ms=5000,
    max_response_bytes=64 * 1024 * 1024,
    verify_tls=True,
    ca_bundle="/path/to/private-ca.pem",
)
var store = S3Store(config, transport^)
```

Transport values default to 30 seconds total, 5 seconds connection, 64 MiB
buffered response, TLS verification enabled, and libcurl's default trust store.
Timeouts must be positive and response limit nonnegative. Per-attempt timeouts
are not a total operation deadline: retries and backoff extend elapsed time.
Response headers have a separate 64 KiB limit. XML input has an 8 MiB limit.
File downloads bypass buffered body limits and need adequate disk space.

Retries cover selected transport failures and HTTP statuses for replay-safe
operations. Each attempt is re-signed; streamed files rewind/reset before retry.
Retry-After delta/date delays are capped at 60 seconds. Multipart initiation and
completion are not replayed automatically. Repeating PUT on a versioned bucket
can create multiple versions. Cancellation and an overall operation deadline
are not yet available.
