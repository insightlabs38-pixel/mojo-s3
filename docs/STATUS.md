# SDK checkpoint — October 5, 2026

Version **0.1.0-dev** remains unreleased. SDK phase-2 work is on `sdk/s3-phase2`,
based on `sdk/release-readiness` commit `44faa2af60d0e5f476bbc6138794a87b852bb8df`.
Main remains `1c8afa72581e51c1437d6cfedbea4d0a814fb607`. Runtime investigation and
patches remain outside SDK history. No release/tag/upstream issue/PR was created.

Baseline hosted CI [37248323851](https://github.com/insightlabs38-pixel/mojo-s3/actions/runs/37248323851)
passed ordinary checks, examples, source installation, MinIO, ZEROS3 and ASan.
Phase-2 [hosted CI](https://github.com/insightlabs38-pixel/mojo-s3/actions?query=branch%3Asdk%2Fs3-phase2)
tracks the pushed branch; check the exact commit and completed conclusion.

New typed copy/batch delete/HeadBucket, conditions/opaque versions, object storage/
encryption options, four full-object checksums, experimental refreshing workload
providers, ranged downloads and coordinating-thread progress/cancellation are
specified in [PHASE2.md](PHASE2.md). Every new claim is bounded by actual tests.

Mojo 1.1.0 Linux x86-64 remains the tested released baseline. No ARM64/macOS
execution environment is available; pthread_tryjoin_np is Linux-only. Exact
nightly 1.2.0.dev2026100406 is used only with a separate reconstructed TSan closure.
AWS is not executed; its explicit existing-bucket/prefix harness is compiled and
refuses missing authorization. See AWS_QUALIFICATION.md and COMPATIBILITY.md.

The original candidate-runtime qualification passed genuine race detection and
the unchanged strict SDK gate plus live/STS/TLS/stress. A later phase-2 strict
run with the current LLVM runtime exposed an intermittent OpenSSL-internal TSan
warning in the unchanged cold-start thread smoke. That failed gate is retained;
no check/suppression was changed. Individual new-threaded-path evidence is
recorded separately. Neither a clean supported released TSan runtime nor general
SDK/native-dependency race freedom is claimed.

Source packaging is deterministic with checksums/build information and a gated
manual dry-run workflow. No registry OIDC process is invented, token stored or
package published. Three upstream investigation bundles remain separate, with
the original downloaded ZIPs remain byte-preserved. The authorized remote
recovery branch was deleted; local recovery history remains.


Convergence adds dynamic Int64 multipart planning and streamed file ranges,
per-worker download result storage, server-side multipart copy, bounded upload
inspection, version-aware tag operations and signed one-hop AssumeRole. These
additional interfaces remain experimental. Current qualification and deferrals
are consolidated in [CONVERGENCE.md](CONVERGENCE.md). The matched OpenSSL controls
now distinguish invisible uninstrumented hash-table synchronization from a
separate source-level cold allocation race. An isolated fully instrumented
closure passes the unchanged strict gate; the released-toolchain limitation above
remains. Exact-head hosted CI must be checked after the convergence push.
