"""Linux file ownership and incremental hashing for bounded-memory transfers."""
from std.collections import List
from std.ffi import external_call
from std.memory import Pointer
from mojo_s3.crypto import hex_encode
from mojo_s3.checksums import crc_update, crc_bytes

comptime Raw = Pointer[UInt8, MutUntrackedOrigin]


struct NativeFile(Movable):
    var fd: Int32
    var path: String
    var temporary: Bool

    def __init__(out self, path: String, temporary: Bool = False) raises:
        if path.find("\x00") >= 0:
            raise Error("Local file paths must not contain NUL")
        self.path = path
        self.temporary = temporary
        self.fd = -1
        if temporary:
            self.path += ".mojo-XXXXXX"
            # mkstemp mutates exactly the six X bytes, preserving string length.
            var c_path = self.path.as_c_string_span()
            self.fd = external_call["mkstemp", Int32](
                c_path.ptr().unsafe_mut_cast[True]()
            )
        else:
            var c_path = self.path.as_c_string_span()
            self.fd = external_call["open", Int32, num_fixed_args=2](
                c_path, Int32(0x80000)
            )
        if self.fd < 0:
            raise Error("Cannot open local transfer file")

    def __deinit__(deinit self):
        if self.fd >= 0:
            _ = external_call["close", Int32](self.fd)
        if self.temporary:
            var path = self.path
            _ = external_call["unlink", Int32](path.as_c_string_span())

    def rewind(self) raises:
        if external_call["lseek", Int64](self.fd, Int64(0), Int32(0)) < 0:
            raise Error("Transfer file must be seekable")

    def reset(self) raises:
        self.rewind()
        if external_call["ftruncate", Int32](self.fd, Int64(0)) < 0:
            raise Error("Cannot reset transfer file")

    def length(self) raises -> Int:
        var size = external_call["lseek", Int64](self.fd, Int64(0), Int32(2))
        if size < 0:
            raise Error("Transfer file must be seekable")
        self.rewind()
        return Int(size)

    def commit(mut self, destination: String) raises:
        if external_call["fsync", Int32](self.fd) != 0:
            raise Error("Cannot sync downloaded file")
        var target = destination
        var path = self.path
        if (
            external_call["rename", Int32](
                path.as_c_string_span(), target.as_c_string_span()
            )
            != 0
        ):
            raise Error("Cannot commit downloaded file")
        self.temporary = False


struct DigestContext(Movable):
    var ptr: Raw

    def __init__(out self) raises:
        var p = external_call["EVP_MD_CTX_new", Optional[Raw]]()
        if not p:
            raise Error("Cannot allocate SHA256 context")
        self.ptr = p.value()

    def __deinit__(deinit self):
        external_call["EVP_MD_CTX_free", NoneType](self.ptr)


def errno_value() -> Int:
    return Int(
        external_call[
            "__errno_location", Pointer[Int32, MutUntrackedOrigin]
        ]()[]
    )


def digest_file_range(
    file: NativeFile, offset: Int64, length: Int64, algorithm: String = "sha256"
) raises -> List[UInt8]:
    if offset < 0 or length < 0 or offset > Int64(9223372036854775807) - length:
        raise Error("Invalid file digest range")
    if algorithm not in ["sha256", "sha1", "crc32", "crc32c"]:
        raise Error("Unsupported file checksum algorithm")
    var context = DigestContext()
    var crc = UInt32(0xFFFFFFFF)
    var is_crc = algorithm == "crc32" or algorithm == "crc32c"
    if not is_crc:
        var native_algorithm = (
            external_call["EVP_sha256", Raw]() if algorithm
            == "sha256" else external_call["EVP_sha1", Raw]()
        )
        if (
            external_call["EVP_DigestInit_ex", Int32](
                context.ptr, native_algorithm, Optional[Raw](None)
            )
            != 1
        ):
            raise Error("Cannot initialize file digest")
    var buffer = List[UInt8](length=65536, fill=0)
    var consumed = Int64(0)
    while consumed < length:
        var requested = min(Int64(len(buffer)), length - consumed)
        var n = external_call["pread", Int64](
            file.fd, buffer.unsafe_ptr(), requested, offset + consumed
        )
        if n < 0 and errno_value() == 4:
            continue
        if n <= 0:
            raise Error("Cannot read stable file digest range")
        if is_crc:
            crc = crc_update(buffer, Int(n), crc, algorithm)
        elif (
            external_call["EVP_DigestUpdate", Int32](
                context.ptr, buffer.unsafe_ptr(), Int(n)
            )
            != 1
        ):
            raise Error("File digest update failed")
        consumed += n
    if is_crc:
        return crc_bytes(crc)
    var digest = List[UInt8](length=32 if algorithm == "sha256" else 20, fill=0)
    var output_length = UInt32(0)
    if external_call["EVP_DigestFinal_ex", Int32](
        context.ptr, digest.unsafe_ptr(), Pointer(to=output_length)
    ) != 1 or Int(output_length) != len(digest):
        raise Error("File digest finalization failed")
    return digest^


def digest_file(
    file: NativeFile, algorithm: String = "sha256"
) raises -> List[UInt8]:
    return digest_file_range(file, 0, Int64(file.length()), algorithm)


def hash_file(file: NativeFile) raises -> String:
    return hex_encode(digest_file(file))
