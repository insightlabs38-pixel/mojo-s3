# 0.1 public-surface freeze review

This freezes feature scope, not experimental layout stability. Reviewed on
October 5, 2026 against the RC preparation delta and the preserved convergence
implementation. No compatibility class was promoted merely because tests pass.

| Surface | Decision / invariant |
|---|---|
| Core S3Store/ObjectStore/config/static credentials/results/ranges | Intended stable source API; synchronous, one mutable store per execution context, owned results. Existing defaults preserved. |
| MultipartPlan | Experimental; Int64 byte sizes/offsets and allocation-free protocol bounds. Buffer budgets describe payload buffers, not process memory. |
| ListParts/ListMultipartUploads | Experimental; owned bounded pages, opaque upload IDs, caller-controlled bounded paginator; no mutation of discovered uploads. Backend defects do not weaken validation. |
| Multipart copy / tagging | Experimental; explicit source identity/tag directive, encoded headers/XML, malformed/embedded success fails; abort preserves primary error and orphan ID. |
| AssumeRole/workload refresh | Experimental; owned one-hop source description, independent caches, fail-closed expiration, explicit trusted endpoints; no role chaining. Credentials are not zeroized. |
| TransferControl/ProgressObserver | Experimental; owned heap state, coordinator callbacks, cooperative cancellation, every launched worker joins. The observer uses cancel_requested without storing a raw alias. Do not mutate internal state/layouts or share a store concurrently. |
| ObjectVersion/DeleteMarker/VersionsPage | Experimental; separate owned lists, opaque IDs, checked Int64 size_bytes, explicit latest flag, common prefixes. Lists preserve category order, not a reconstructed cross-category global order. ETags never imply MD5. |
| VersionsPaginator/list_object_versions | Experimental; prefix/delimiter/key marker/version marker, page size 1–1000. No lexical version-ID or time ordering assumptions; bounded page budget and marker-cycle detection. Failed pages do not advance state. Serialized marker state is not persisted-resume support. |
| Checksum metadata | Existing explicit absent/unverified/composite/verified state; unsupported CRC64NVME stays unverified. No full-object inference from multipart composite values. |

Result data may be mutated by its owner. Paginator coordination fields are
observable but callers must not alter them during traversal; `_seen_markers`
and native callback/worker/transport fields remain internal. Keep explicit
marker strings unchanged when restarting a bounded traversal. Retries follow
existing idempotency rules; listing introduces only signed GET requests.

External source installation compiles the root public-facade consumer, including
new page/result/paginator constructors. Native version integration exercises the
root listing function. Deterministic fixtures verify opaque query IDs, encoded
keys, duplicates, bounds, overflow, missing booleans/fields and marker cycles;
local versioned MinIO verifies versions/delete markers/delimiters and known-ID
cleanup. Current Versity pagination is separately classified as a backend
deviation. No API permits bucket versioning configuration or automatic cleanup.
