# Roadmap

Current target: **0.1.0-dev**, an unreleased development version. A release
candidate requires completed ordinary/ASan/contract checks, a verified clean
installation, compiled examples, documented API, current compatibility evidence,
a completed security review and no known critical corruption bug. A documented
upstream TSan runtime blocker is distinct from passing race qualification.

## Release-critical

Local source installation, API/provider documentation, ordinary/backend/ASan
checks and direct source security review passed in this iteration. Before release:

- Review and publish the chosen SDK source revision through the authorized process.
- Execute hosted CI and verify installation from the published revision.
- Keep API/configuration/credential/transfer contracts aligned as changes land.
- Preserve the strict TSan gate; qualify a supported released fixed runtime.
- Decide which AWS/platform/compiler combinations to claim using executed evidence.

## Near-term

- Improve credential providers and explicit refresh semantics for applications/CI.
- Regional AWS configuration ergonomics and authorized isolated AWS qualification.
- Extend bounded pagination and suffix range interoperability coverage.
- Extend the transfer layer with cancellation and progress; evaluate concurrent
  downloads after failure/atomicity design.
- Qualify adjacent Mojo versions and Linux ARM64; investigate macOS ABI/build work.
- Broaden integrity and fuzz/property qualification where evidence shows gaps.

## Future

- Resume multipart with durable source identity and explicit cleanup semantics.
- Additional object-store backends and ecosystem adapters after S3 API maturity.
- Focused useful S3 capabilities such as copy and conditional requests.

These priorities are not delivery promises. Windows, full AWS management APIs,
backend-specific storage internals and speculative abstractions are outside the
initial release scope. See [STATUS.md](STATUS.md) for current execution results
and [COMPATIBILITY.md](COMPATIBILITY.md) for backend-specific limitations.
