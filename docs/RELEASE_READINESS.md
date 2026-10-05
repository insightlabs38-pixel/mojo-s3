# Release-readiness report — October 4, 2026

The local iteration delivers a tested source installation and complete credential,
range, pagination and file-transfer improvements. Recommended version remains
**0.1.0-dev** until a reviewed, published source revision and hosted release checks
exist. No release candidate or production-readiness claim is made.

## Delivered surface and migration

The root facade exports common store/config/result/options/range/pagination types
and experimental transfer types. [API.md](API.md) distinguishes intended stable,
experimental and internal APIs and documents owned results, one-owner stores,
request-associated `last_error` and source/compiler compatibility.

`S3Config.from_env()` now resolves one complete S3 or AWS environment identity;
partial identities fail instead of mixing keys across providers. Without a custom
endpoint it generates regional AWS HTTPS/virtual-host defaults. With `S3_ENDPOINT`
it defaults to path style and retains the caller's independent signing region.
`from_default()` additionally supports static AWS shared credentials/config profiles.
The explicit constructor remains available for generic endpoints. These factory
behavior changes are documented in CONFIGURATION.md and CREDENTIALS.md.

`ObjectRange.suffix(n)` adds positive suffix requests. `ListPaginator` returns one
owned raw page at a time, rejects empty/nonadvancing continuation tokens and bounds
page count. `TransferManager` owns its store and selects streaming or sequential/
concurrent multipart for files; existing retry, SHA256 and cleanup behavior is
retained. Its configured part-buffer ceiling excludes payload copies, response
buffers and native overhead. Progress, cancellation, refresh and concurrent
ranged downloads are not implemented.

## Local verification

| Check | Result and scope |
|---|---|
| Ordinary `scripts/check` | Passed on Mojo 1.1.0: precompile, all unit/fixture/property/fault/TLS checks and every example |
| New fixtures | Credential precedence/profiles/session/regions, suffix coherence/paginator bounds, transfer threshold/buffer policy passed |
| `scripts/check-release` | Passed: metadata, source archive, fresh install with spaces, independent consumer constructing the manager, refusal to mix installations |
| MinIO 2025-04-22 | Updated common contract, file transfers, all manager selections, 1/2/4/8-worker multipart, local STS, full-object SHA256, boto3 interoperability and stress passed |
| Versity 1.0.16 POSIX | Updated common contract, streaming, multipart, 1/2/4/8 workers and all manager selections passed; official release archive checksum verified |
| ZEROS3 f391b7e | Updated common/extended-key contracts, file/multipart/manager roundtrips, interoperability and verified virtual-host HTTPS passed |
| AddressSanitizer | Native threads, fault cleanup, updated MinIO contract/manager/multipart, verified ZEROS3 HTTPS passed |
| Isolated nightly ThreadSanitizer | Intentional Mojo race reported exit 66; unchanged baseline strict/live/STS/HTTPS/stress checks passed. New feature fixtures and updated live contract/manager also passed |
| Security review | Direct source review completed for documented boundaries; formal scan unavailable, no exhaustive audit claim. See SECURITY_REVIEW.md |
| Hosted CI | Workflow updated with package/install and new manager checks; not executed on GitHub Actions |

TSan results require the exact experimental nightly/runtime closure in TSAN.md.
Mojo 1.1.0's packaged runtime remains blocked before main. There were no suppressed
checks, SDK-baseline edits or released-runtime qualification claims.

## Packaging, dependencies and platforms

The source archive contains SDK source, examples, tests, docs, MIT license,
VERSION/changelog/project metadata and install/build scripts. It excludes generated
packages, build outputs, research bundles and caches. The installed helper supplies
import paths and native curl/crypto/XML linkage. It is tested outside the repository.
`package.json` is descriptive metadata; it is not a registry installation promise.
MojoShelf's experimental source-tin approach was evaluated from its current public
specifications; CLI/Pixi/native-linker integration and publication remain untested.

Linux x86-64 with Mojo 1.1.0 is the adoption baseline. ARM64/macOS require actual
ABI/build/integration execution; Windows is outside current POSIX support.
Dependencies are retained with rationale in DEPENDENCIES.md: libcurl 8.14.1,
OpenSSL 3.5.7 and Debian's security-patched libxml2 2.9.14 were observed here.
No portable compiled `.mojoc` ABI or independently qualified oldest library baseline
is promised. Compiled client operations require no CPython or subprocess transport.

## Remaining release work and next priorities

1. Review this local SDK branch and run the authored hosted CI before selecting a
   release revision. No pushes, tags, issues or PRs were submitted in this run.
2. Validate published installation from that revision and qualify any desired
   MojoShelf/Pixi route with the native linker requirements.
3. Run an isolated, explicitly authorized AWS bucket contract when an identity is
   available; published signing fixtures do not establish live AWS compatibility.
4. Rerun the unchanged TSan gate with a supported upstream-fixed runtime. Local
   rebuilding succeeded, but upstream landing and release packaging remain external.
5. Extend the transfer API with carefully specified progress/cancellation and
   concurrent-download atomicity; add refreshing providers with expiration and
   thread-ownership semantics before claiming role/workload identity support.
6. Qualify ARM64/macOS and adjacent released Mojo versions on actual environments.

The broader goal's optional S3 breadth and backend adapters remain roadmap work.
No new throughput or memory benchmark was run; existing BENCHMARKS.md observations
retain their original conditions. No fastest/production-ready claim is made.

Detailed execution logs and runtime artifacts are local under the separate
investigation's evidence directory; runtime research is deliberately excluded from
this SDK distribution. STATUS.md and COMPATIBILITY.md record current SDK results.
