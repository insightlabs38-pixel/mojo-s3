"""OpenSSL digest bindings. No custom cryptographic algorithms."""
from std.ffi import external_call
from std.memory import Pointer
from std.collections import List

comptime Raw = Pointer[UInt8, MutUntrackedOrigin]


def hex_encode(data: List[UInt8]) -> String:
    var result = String()
    var digits = "0123456789abcdef"
    for b in data:
        result += String(digits[byte=Int(b) >> 4])
        result += String(digits[byte=Int(b) & 15])
    return result^


def bytes_of(text: String) -> List[UInt8]:
    var result = List[UInt8](capacity=text.byte_length())
    for b in text.as_bytes():
        result.append(b)
    return result^


def sha256(data: List[UInt8]) raises -> List[UInt8]:
    var result = List[UInt8](length=32, fill=0)
    var ptr = external_call["SHA256", Optional[Raw]](
        data.unsafe_ptr(), len(data), result.unsafe_ptr()
    )
    if not ptr:
        raise Error("OpenSSL SHA256 failed")
    return result^


def sha256_hex(data: List[UInt8]) raises -> String:
    return hex_encode(sha256(data))


def hash_text(text: String) raises -> String:
    return sha256_hex(bytes_of(text))


def hmac_sha256(key: List[UInt8], data: List[UInt8]) raises -> List[UInt8]:
    var result = List[UInt8](length=32, fill=0)
    var length = UInt32(0)
    var digest = external_call["EVP_sha256", Raw]()
    var ptr = external_call["HMAC", Optional[Raw]](
        digest,
        key.unsafe_ptr(),
        Int32(len(key)),
        data.unsafe_ptr(),
        len(data),
        result.unsafe_ptr(),
        Pointer(to=length),
    )
    if not ptr or length != 32:
        raise Error("OpenSSL HMAC-SHA256 failed")
    return result^


def random_token() raises -> String:
    """Generate a random 128-bit identifier, useful for isolated test prefixes."""
    var data = List[UInt8](length=16, fill=0)
    if external_call["RAND_bytes", Int32](data.unsafe_ptr(), Int32(16)) != 1:
        raise Error("OpenSSL random generator failed")
    return hex_encode(data)


def base64_encode(data: List[UInt8]) raises -> String:
    if len(data) > 1024 * 1024:
        raise Error("Digest encoding input too large")
    var output = List[UInt8](length=((len(data) + 2) // 3) * 4 + 1, fill=0)
    var n = external_call["EVP_EncodeBlock", Int32](
        output.unsafe_ptr(), data.unsafe_ptr(), Int32(len(data))
    )
    if n < 0:
        raise Error("OpenSSL Base64 encoding failed")
    return String(from_utf8=Span(unsafe_ptr=output.unsafe_ptr(), length=Int(n)))
