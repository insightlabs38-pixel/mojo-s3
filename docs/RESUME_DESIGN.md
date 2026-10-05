# Deferred resumable multipart design

No persisted resume API ships in this development checkpoint. ListParts and
explicit multipart lifecycle operations provide inspection primitives, not proof
that bytes still belong to the same source. Never resume by scanning a bucket or
matching a path/mtime alone; never auto-abort unrelated discovered upload IDs.

A future explicit record must contain a schema version, endpoint/region/bucket/
key, opaque upload ID, Int64 file size and full source digest, exact planner
parameters, destination options, and each confirmed part number/ETag. Record
writes require atomic replacement and restrictive permissions; tokens and source
credentials must be excluded. Reopening must recompute source identity and cross-
check ListParts with the persisted manifest, reject duplicate/out-of-range parts
and conflicting ETags/sizes, and bind resumed requests to the same endpoint and
object. Completion ambiguity needs an explicit reconciliation policy rather than
blind initiation or automatic rollback. Fault coverage must include stale source,
truncated records, mismatched server parts, orphan IDs and lost completion replies.

This work is deferred until those invariants and failure paths have independent
oracles. Existing primitives do not infer safe resume from file modification time.
