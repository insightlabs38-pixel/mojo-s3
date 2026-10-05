# Security and operational boundaries

This is development software, version 0.1.0-dev. The following documents current
controls and limitations; it is not a completed security audit or production
qualification claim.

TLS certificate and hostname verification are enabled by default. Use a private
CA bundle instead of disabling verification. HTTP endpoints expose credentials'
authenticated requests and object content to the network; use them only for
explicit local fixtures or an appropriately controlled environment. Redirects
are disabled so signed requests are not forwarded to another host.

Credentials are copied into ordinary Mojo strings; secure-memory storage and
zeroization are not promised. Do not log Authorization headers, session tokens,
canonical signing requests, or presigned URLs. Presigned URLs are bearer
capabilities until expiration (or earlier credential expiration/revocation).
Return them only to authorized consumers and send every signed header unchanged.
Server error fields, object names and metadata are untrusted text: redact and
sanitize them before displaying in logs. Do not log arbitrary error bodies.

Buffered responses default to 64 MiB, headers to 64 KiB and XML input to 8 MiB.
XML depth/node bounds apply; DTD/entity-reference nodes are rejected and network
loading disabled. Headers and protocol fixtures exercise injection-sensitive
inputs. Streaming downloads bypass the buffered payload ceiling, so callers must
manage disk quotas and trusted destination directories. Object keys are raw
service names, not local paths; do not concatenate keys into local file paths.

Downloads use secure temporary files beside the destination and validate length
and supported SHA-256 before atomic replacement. Existing destinations are
replaced on success. Caller-selected directories and unchanged upload sources
are required; files are not locked and parent directories are not fsynced.
Multipart helpers abort on failure; abort failure leaves an upload ID requiring
operator cleanup. ETags, unsupported algorithms and composite checksums do not
prove object integrity.

One store/transport must have one active owner. Parallel multipart workers use
independent stores. ASan and worker failure tests provide memory/failure evidence;
Mojo 1.1.0's released allocator/runtime still blocks the strict [TSan gate](TSAN.md)
before user main. An isolated matching-nightly experiment passed the unchanged
baseline gate and live checks; this does not qualify the released runtime or prove
race freedom.

For a suspected vulnerability, use the repository host's private vulnerability
reporting facility if available. If it is unavailable, request a private contact
channel without disclosing exploit details, credentials or private endpoints in
a public issue. No project-specific security email or response SLA is currently
established. Provide affected commit/compiler/native-library versions, impact and
a minimal reproduction using synthetic credentials. Ordinary compatibility bugs
can follow [CONTRIBUTING.md](../CONTRIBUTING.md).
