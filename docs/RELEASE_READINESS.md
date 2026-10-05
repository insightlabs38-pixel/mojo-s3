# Release decision — October 5, 2026

Remain **0.1.0-dev**. Feature scope is frozen for this preparation pass; no tag,
publication or main merge is authorized. [RC_CONVERGENCE.md](RC_CONVERGENCE.md)
and the supplemental final report identify actual executed evidence and exact CI.
The classification below separates SDK release blockers from optional-backend
limitations and experimental production sanitizer support.

| Item | Classification | Current evidence / closure required |
|---|---|---|
| Live AWS against authorized existing bucket/prefix | **Blocker (final release)** | No credentials attached; opt-in harness compiles/refuses unauthorized use. Owner must explicitly authorize and provide the existing resources, run it and retain cleanup evidence. Local backends are not AWS proof. |
| Exact-head hosted CI and ordinary/ASan gates | **Blocker if not green** | Final handoff must record completed CI for the pushed head, ordinary gate and new ASan fixtures. A prior green head is insufficient. |
| Deterministic source artifact / clean installation | **Blocker if not green** | Byte-identical double build, inner checksums/BUILDINFO and external public consumer/install required at final head. |
| API review / docs / SDK corruption | **Blocker if unresolved** | API_FREEZE.md keeps implementation-shaped surfaces experimental. No known SDK corruption identified in focused review; the listing space/plus identity bug is fixed and malformed version-marker cycles fail closed. Not a formal audit. |
| Current MinIO and Versity classification | **Non-blocker after classification** | Exact stable versions independently tested; optional listing limitations explicitly documented. CI retains old immutable MinIO pin because latest fails the full extension contract; current local suite is separate evidence. |
| ZEROS3 UploadPartCopy | **Non-blocker for AWS-target SDK; extension unsupported on this backend** | HTTP 200 without CopyPartResult fails; no backend change or parser relaxation. Baseline support remains distinct. |
| OpenSSL allocator flag race | **Non-blocker for ordinary SDK; dependency limitation for sanitizer claims** | Reproduced independently on current stable/development builds. Original hash warning is a separate instrumentation boundary. Local issue-quality report, no suppression/submission. |
| Distribution activation | **Recommended before RC; blocker for publication** | Deterministic source route is qualified; user must choose/authorize release settings and publication. No registry/account setup performed. |
| Versioned AWS / KMS / cross-account controls | **Recommended before corresponding support claims** | Local versioned fixtures and request construction do not qualify AWS account policy. Separate explicit resource authorization needed. |
| Released Mojo TSan / Modular production selector | **Deferred after RC** | Experimental matching-nightly closure only. Private maintainer hook remains; no production sanitizer support claim. |
| CRC64NVME / multipart checksum negotiation / persisted resume | **Deferred after RC** | Design/invariants preserved; no fake composite verification or inferred safe resume. |
| ARM64/macOS / compiled ABI / additional backends | **Deferred after RC** | Linux x86-64, source distribution and current tested subsets only. |

When exact-head CI, ordinary/ASan, deterministic installation, current backend
classification and API/doc gates are green, the highest-value next action is an
**explicitly authorized live AWS qualification pass**, not another feature phase.
The project can be technically RC-quality within its documented experimental
scope while remaining development-version software pending AWS evidence and
owner distribution activation. No automatic version bump is justified.

Owner checklist:

1. Supply an explicitly authorized existing AWS bucket/prefix and cleanup policy;
   approve additional preconfigured versioned/KMS resources only if those claims
   are to be qualified. Never change account settings implicitly.
2. Review exact-head CI, API freeze, current backend limits and deterministic
   source artifact/consumer results.
3. Choose the future version/tag and source distribution route; authorize that
   separate publication only after the qualification record is complete.
