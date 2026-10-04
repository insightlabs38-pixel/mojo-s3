from std.collections import List
from std.testing import assert_equal
from mojo_s3.crypto import hash_text, hmac_sha256, bytes_of, hex_encode


def main() raises:
    assert_equal(
        hash_text(""),
        "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    )
    assert_equal(
        hash_text("abc"),
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
    )
    assert_equal(
        hex_encode(
            hmac_sha256(
                bytes_of("key"),
                bytes_of("The quick brown fox jumps over the lazy dog"),
            )
        ),
        "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8",
    )
    var key = List[UInt8](length=20, fill=0x0B)
    assert_equal(
        hex_encode(hmac_sha256(key, bytes_of("Hi There"))),
        "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7",
    )
    var long_key = List[UInt8](length=131, fill=0xAA)
    assert_equal(
        hex_encode(
            hmac_sha256(
                long_key,
                bytes_of(
                    "Test Using Larger Than Block-Size Key - Hash Key First"
                ),
            )
        ),
        "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54",
    )
    var million_a = List[UInt8](length=1000000, fill=97)
    from mojo_s3.crypto import sha256_hex

    assert_equal(
        sha256_hex(million_a),
        "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0",
    )
    print("crypto vectors passed")
