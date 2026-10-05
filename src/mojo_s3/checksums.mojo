"""Full-object checksum algorithms; composite values are preserved, not verified."""
from std.collections import List
from std.ffi import external_call
from std.memory import Pointer
from mojo_s3.crypto import sha256, base64_encode
from mojo_s3.protocol import Field, get_header

comptime ChecksumRaw = Pointer[UInt8, MutUntrackedOrigin]


def crc_update(
    data: List[UInt8], length: Int, state: UInt32, algorithm: String
) raises -> UInt32:
    if algorithm != "crc32" and algorithm != "crc32c":
        raise Error("Unsupported CRC algorithm")
    if length < 0 or length > len(data):
        raise Error("Invalid CRC input length")
    var crc = state
    var polynomial = UInt32(0xEDB88320 if algorithm == "crc32" else 0x82F63B78)
    for i in range(length):
        crc ^= UInt32(data[i])
        for _ in range(8):
            crc = (crc >> 1) ^ (polynomial if crc & 1 else UInt32(0))
    return crc


def crc_bytes(state: UInt32) -> List[UInt8]:
    var value = ~state
    var bytes = List[UInt8]()
    for shift in [24, 16, 8, 0]:
        bytes.append(UInt8((value >> UInt32(shift)) & 255))
    return bytes^


def checksum_digest(data: List[UInt8], algorithm: String) raises -> List[UInt8]:
    if algorithm == "sha256":
        return sha256(data)
    if algorithm == "crc32" or algorithm == "crc32c":
        return crc_bytes(
            crc_update(data, len(data), UInt32(0xFFFFFFFF), algorithm)
        )
    if algorithm == "sha1":
        var result = List[UInt8](length=20, fill=0)
        if not external_call["SHA1", Optional[ChecksumRaw]](
            data.unsafe_ptr(), len(data), result.unsafe_ptr()
        ):
            raise Error("OpenSSL SHA1 checksum failed")
        return result^
    raise Error("Unsupported S3 checksum algorithm")


def supplied_checksum(headers: List[Field]) -> Field:
    for algorithm in ["sha256", "crc32c", "crc32", "sha1", "crc64nvme"]:
        var value = get_header(headers, "x-amz-checksum-" + algorithm)
        if value:
            return Field(algorithm, value)
    return Field("", "")


def full_checksum(headers: List[Field]) -> Field:
    var supplied = supplied_checksum(headers)
    var kind = get_header(headers, "x-amz-checksum-type")
    if (
        supplied.name == "crc64nvme"
        or kind == "COMPOSITE"
        or (not kind and "-" in supplied.value)
        or (kind and kind != "FULL_OBJECT")
    ):
        return Field("", "")
    return supplied^
