# ThreadSanitizer runtime qualification

Mojo 1.1.0's unmodified packaged runtime still aborts before user main under
ThreadSanitizer. It is not dynamically qualified. The strict `scripts/check-tsan`
gate remains unchanged.

An isolated local experiment on October 4, 2026 successfully qualified the
unchanged SDK at `1c8afa72581e51c1437d6cfedbea4d0a814fb607` with the exact matching
Mojo nightly **1.2.0.dev2026100406 (1b9d9b9b)**, a corrected LLVM TSan interceptor,
and rebuilt sanitizer-instrumented Modular AsyncRT/Support dependencies. A real
intentional Mojo race was detected with exit 66 before running SDK tests.
Repeated hello/constructor probes, the unchanged strict gate, live 1/2/4/8-worker
multipart, failure/cleanup tests, local temporary credentials, verified HTTPS
with a custom CA, and multiprocess stress all passed. No SDK test, suppression
or instrumentation check was weakened to obtain this baseline result.

This is experimental evidence for that pinned dependency closure, not a fixed
released toolchain, arbitrary cross-version ABI guarantee or proof of race freedom.
Research, rebuilt libraries, toolchain selection and detailed logs remain outside
this SDK. Ordinary installation does not install or select experimental runtimes.
Use a supported upstream fixed runtime for release qualification when available.

## Reproduce and resume

```sh
RUN_TSAN_TRACE=1 scripts/check-tsan
```

This compiles and executes a minimal `print("hello")` program with no SDK imports
in ordinary, AddressSanitizer, and ThreadSanitizer modes. It records versions,
resource limits, CPU information, cgroups, ELF dependencies and optional focused
mmap tracing under ignored `build/sanitizers/`. An execution failure exits 99 and
prevents SDK concurrency tests from running. A compilation failure also fails the
command. A successful compilation alone never passes this gate.

Once all three minimal executions pass, the same command builds and runs native
thread smoke and concurrent failure/cleanup tests with `--sanitize thread`.
Set `RUN_S3_INTEGRATION=1` and the isolated bucket/source environment described in
DEVELOPMENT.md to additionally run real multipart at 1/2/4/8 workers. The strict
gate uses the unchanged application sources, with no sanitizer suppressions or
allocator substitution. A manually dispatched GitHub workflow retains its logs.

## Observations on October 4, 2026

Initial repository HEAD: `7ade2a3392da863b834d5b9078b44553db71f87e`, branch `work`.
The SDK was uncommitted, with README changed and source/tests/scripts/docs/CI new.

| Environment | Mojo | Ordinary | AddressSanitizer | ThreadSanitizer |
| --- | --- | --- | --- | --- |
| Host Debian 13, glibc 2.41, libtsan 14.2.0-19 | 1.1.0 (8189361e) | exit 0 | exit 0 | abort 134 |
| Host outside Codex filesystem sandbox | same 1.1.0 binary | previously passed | previously passed | abort 134 |
| Clean Ubuntu 24.04.5, glibc 2.39, libtsan 14.2.0-4ubuntu2~24.04.1 | same 1.1.0 binaries/runtime libraries | exit 0 | exit 0 | abort 134 |
| Clean Debian 12, glibc 2.36, GCC 13.5.0 (`gcc:13` image) | same 1.1.0 binaries/runtime libraries | exit 0 | exit 0 | abort 134 |
| Host alternate released compiler | 1.0.0 (ed45d567) | not repeated | not repeated | minimal abort 134 |

Ubuntu image digest:
`sha256:534baea6a22c03a63003dbc8dbe78fe34bc0d7e595d9a9dc9834884ff530eb55`.
GCC 13 image digest:
`sha256:16ae525998c94df36a116c191524256b1d46e72d7a0e9aaf6c153455e40eb5b8`.
The binaries and three unchanged Mojo runtime shared libraries were copied into
ephemeral containers; `LD_LIBRARY_PATH` selected those libraries. Each container
supplied its own libc/libstdc++/libgcc/libtsan. They share the host kernel, so this
is independent userspace evidence, not qualification on a second physical host.

Host: x86-64 KVM, Linux 6.18.44, AVX2 and AVX-512 available; 64-bit userspace;
CPU reports 46-bit physical/57-bit virtual address capability. RLIMIT_AS and
RLIMIT_DATA are unlimited; stack soft limit is 8 MiB, hard unlimited; memlock
8 MiB. Cgroup memory.max is 8 GiB, memory.high/swap.max/pids.max are unlimited;
about 7.6 GiB host-visible memory was available, with no swap. vm.max_map_count
65530, vm.overcommit_memory 0, ratio 50. None explains repeated fixed mappings at
address zero. No LD_PRELOAD or sanitizer/allocator environment overrides were
present. No kernel settings, resource limits, or installed runtime libraries
were changed.

## Actual failure

The minimal executable resolves `libtsan.so.2` from the system and
`libKGENCompilerRTShared.so`, `libMSupportGlobals.so` and
`libAsyncRTRuntimeGlobals.so` from the Mojo wheel. Focused `strace`, including a
stack trace, shows the failing syscall before the tcmalloc arena abort:

```text
mmap(NULL, 1073741824, PROT_NONE,
     MAP_PRIVATE|MAP_ANONYMOUS|MAP_FIXED_NOREPLACE, -1, 0)
    = -1 EPERM (Operation not permitted)
```

The allocator's diagnostic reports a nonzero tagged hint, for example
`0x4cf580000000`; the kernel instead sees NULL. The GCC 14
[`fix_mmap_addr` interceptor](https://github.com/gcc-mirror/gcc/blob/releases/gcc-14/libsanitizer/tsan/tsan_interceptors_posix.cpp)
clears hints outside TSan application memory. It recognizes MAP_FIXED but not
MAP_FIXED_NOREPLACE in this branch. Clearing a fixed-no-replace hint makes the
request target address zero. The trace passes through libtsan's mmap interceptor,
the bundled tcmalloc allocator, and the dynamic loader's constructor calls.
Ubuntu reproduces the same syscall/errno. This is an address-layout/interceptor
incompatibility, not evidence of exhausted physical RAM.

A separately compiled GCC C/pthread control reaches main on the host, and TSan
reports its intentionally unsynchronized shared integer accesses. This confirms
that the host can execute TSan and detect a real race; it does **not** establish
anything about SDK race freedom. Reproduce this diagnostic control with:

```sh
gcc -fsanitize=thread -g -pthread tests/diagnostics/tsan_control.c -o build/tsan-control
build/tsan-control
```

A TSan data-race report and exit 66 are expected for this deliberately invalid
control. It is excluded from the ordinary passing test suite.

## Repairs attempted and boundary

- Running outside the Codex sandbox does not repair the minimal executable.
- Clean Ubuntu and Debian userspaces reproduce the failure.
- Downgrading one released Mojo version reproduces it.
- The exported `KGEN_CompilerRT_SetAsanAllocators()` hook was inspected against
  Modular source and tested using a temporary linked C constructor. It does not
  repair startup: tcmalloc's own shared-library constructor initializes before
  the executable constructor can switch Mojo allocations. This experimental
  object was not added to SDK builds or the repository.
- The Modular nightly wheel index was attempted, but its HTTPS proxy tunnel was
  unavailable in this environment. No proxy bypass was attempted.

Changing VM limits, disabling ASLR, increasing physical memory, or turning off
checks would not resolve the observed incompatible address selection. A working
Mojo release/runtime with TSan-compatible allocator initialization is required;
the installed binary distribution does not provide a supported allocator switch.
No binary patch, preload allocator shim, mmap interception bypass, sanitizer
suppression, or race-free claim is included. Run the unchanged strict gate with an upstream-fixed supported toolchain before
claiming released-runtime qualification. The isolated experiment above advances
local investigation without changing this released-runtime limitation.

## October 5 phase-2 evidence and unresolved OpenSSL warning

The full 2x2 test distinguishes startup from the LLVM interceptor bug: ordinary
AsyncRT fails with both LLVM variants; the genuinely sanitizer-aware closure
passes loader/hello/race with both. The narrow LLVM fix is independently valid
and not required for that Mojo startup repair. Candidate public Modular filegroup
builds only under the TSan config, but the production wheel/link selection layer
requires maintainer integration.

New download faults, ranged1/2/4/8 odd/small/empty, controlled multipart progress/
cancellation/partial launch and TransferManager passed individually under the
exact isolated nightly/current LLVM closure. ASan passed the same new paths.

A later full strict gate stopped in the unchanged cold-start thread smoke with
an OpenSSL-internal report (symbolized near EVP_SKEYMGMT_get0_imp_settable_params).
Ten focused repeats reported6/10 with current LLVM and3/10 with historical LLVM,
same executable and AsyncRT/Support/CompilerRT. This is an unresolved dependency
diagnostic; uninstrumented OpenSSL's synchronization limits visibility, and these
observations alone do not classify it as a real OpenSSL defect or false positive.
No suppressions, test weakening or silent rerun-to-pass was used. Earlier passing
strict candidate qualification remains preserved, with its limited consistency
clearly stated. Strict check-tsan is byte-identical to baseline; released-Mojo
TSan and a consistently clean entire native closure remain unqualified.
