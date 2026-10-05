# Native dependencies and platform support

SDK operations execute compiled Mojo and native C libraries, without CPython,
boto3, MAX or a subprocess transport. Python may install compiler tooling or run
test orchestration; it is not required by built SDK client operations.

| Dependency | Used surface | Decision and portability cost |
|---|---|---|
| libcurl | Easy handles/options, header lists, C-ABI streaming callbacks, response info, HTTP date parsing | Retain: tested HTTP/TLS, trust, timeouts and connection reuse. Requires shared-library discovery and correct callback/option ABI. A custom replacement adds substantial protocol/security maintenance. |
| OpenSSL libcrypto | SHA-256, HMAC, EVP incremental digest and Base64 | Retain: established cryptography. Requires OpenSSL 3 ABI; TLS belongs to libcurl's selected backend. Removing it would require another native crypto dependency or owned crypto implementation. |
| libxml2 | Bounded pull-reader for S3 responses | Retain: tested XML decoding/namespaces with DTD/entity rejection. Adds one DSO and reader ownership. A small replacement might reduce packaging cost, but must match malicious-input and encoding tests first. |
| libc / pthread | File descriptors, clocks, secure temporary files, rename/fsync, native worker threads | Linux ABI assumptions remain in file/time/concurrency code; these are platform libraries rather than vendored code. |

The build/install helper resolves required DSOs and links them for users. No
third-party library is vendored. Keep native dependencies updated using your OS
security updates. Debian/Ubuntu development packages:

```sh
sudo apt-get install libcurl4-openssl-dev libssl-dev libxml2-dev openssl
```

Mojo **1.1.0 (8189361e)** is the tested compiler. Other compiler releases and
nightlies are unqualified. Compiled `.mojoc` files are compiler-specific: rebuild
from installed source with the consuming compiler; do not assume adjacent Mojo
versions are binary-compatible.

The current Linux build resolves `libcurl.so.4`, `libcrypto.so.3` and
`libxml2.so.2`. libcurl 7.84+ is recommended for thread-safe global initialization;
older curl releases are unqualified for concurrent workers. OpenSSL 3 is required
by library discovery. No independent oldest-supported libxml2 version has been
qualified. The release-readiness environment has libcurl 8.14.1, OpenSSL 3.5.7 and
libxml2 2.9.14 (Debian security-patched package). These are observed test-environment
versions, not minimum version guarantees.

`CRYPTO_LIBRARY`, `CURL_LIBRARY`, and `XML_LIBRARY` override native library paths;
`MOJO` overrides the compiler. See [development](DEVELOPMENT.md) for test tooling.
An executable still needs compatible native DSOs on its deployment host; copying
only an executable or installed Mojo source does not install those DSOs.

## Platform matrix

| Platform | Status |
|---|---|
| Linux x86-64 | Current build/test baseline |
| Linux ARM64 | Unqualified; needs actual compiler/build/FFI/integration evidence |
| macOS | Unqualified; `.dylib` discovery, errno/file flags, clock layout and filesystem durability need porting and tests |
| Windows | Unsupported by current POSIX files/pthread implementation |

Do not infer portability from library availability. Audit hard-coded Linux open
flags, `__errno_location`, pointer/integer widths, libc time storage, pthread
layouts and linker discovery before promoting another platform. Protocol and
signing logic are separate from those ABI boundaries. See [architecture](ARCHITECTURE.md).
