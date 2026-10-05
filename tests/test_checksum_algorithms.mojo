from std.testing import assert_equal, assert_true
from std.collections import List
from mojo_s3.checksums import (
    checksum_digest,
    crc_update,
    crc_bytes,
    full_checksum,
    supplied_checksum,
)
from mojo_s3.crypto import bytes_of, hex_encode, base64_encode
from mojo_s3.protocol import Field


from checksum_oracles import checksum_oracles


def main() raises:
    checksum_oracles()
    var input = bytes_of("123456789")
    assert_equal(hex_encode(checksum_digest(input, "crc32")), "cbf43926")
    assert_equal(hex_encode(checksum_digest(input, "crc32c")), "e3069283")
    assert_equal(
        hex_encode(checksum_digest(bytes_of("abc"), "sha1")),
        "a9993e364706816aba3e25717850c26c9cd0d89d",
    )
    assert_equal(
        hex_encode(checksum_digest(bytes_of(""), "crc32c")), "00000000"
    )
    var state = crc_update(bytes_of("1234"), 4, UInt32(0xFFFFFFFF), "crc32c")
    state = crc_update(bytes_of("56789"), 5, state, "crc32c")
    assert_equal(hex_encode(crc_bytes(state)), "e3069283")
    var headers: List[Field] = [
        Field(
            "x-amz-checksum-crc32c",
            base64_encode(checksum_digest(input, "crc32c")),
        ),
        Field("x-amz-checksum-type", "FULL_OBJECT"),
    ]
    assert_equal(full_checksum(headers).name, "crc32c")
    headers[1] = Field("x-amz-checksum-type", "COMPOSITE")
    assert_equal(full_checksum(headers).value, "")
    assert_true(Bool(supplied_checksum(headers).value))
    print(
        "CRC32/CRC32C/SHA1 vectors, incremental CRC and composite state passed"
    )
