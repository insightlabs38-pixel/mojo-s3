from std.collections import List
from std.testing import assert_equal, assert_true
from mojo_s3.protocol import (
    Field,
    uri_encode,
    canonical_query,
    address,
    normalize_space,
)
from mojo_s3.signing import Credentials, sign
from mojo_s3.crypto import hash_text


def main() raises:
    assert_equal(
        uri_encode("a//b %2F+?&#=é", True), "a//b%20%252F%2B%3F%26%23%3D%C3%A9"
    )
    var q: List[Field] = [Field("z", ""), Field("a", "+"), Field("a", " ")]
    assert_equal(canonical_query(q), "a=%20&a=%2B&z=")
    assert_equal(normalize_space(" \t a  b\t "), "a b")
    var a = address("http://localhost:9000/", "bucket", "a//../+%2F")
    assert_equal(a.url, "http://localhost:9000/bucket/a//../%2B%252F")
    assert_equal(
        address("https://s3.example:443", "bucket", "x", True).host,
        "bucket.s3.example:443",
    )
    var c = Credentials(
        "AKIAIOSFODNN7EXAMPLE", "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY", ""
    )
    var headers: List[Field] = [
        Field("Host", "examplebucket.s3.amazonaws.com"),
        Field("Range", "bytes=0-9"),
        Field("x-amz-content-sha256", hash_text("")),
        Field("x-amz-date", "20130524T000000Z"),
    ]
    var empty = List[Field]()
    var s = sign(
        c,
        "us-east-1",
        "s3",
        "GET",
        "/test.txt",
        empty,
        headers,
        hash_text(""),
        "20130524T000000Z",
    )
    assert_equal(
        s.signature,
        "f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41",
    )
    assert_equal(s.signed_headers, "host;range;x-amz-content-sha256;x-amz-date")
    print("AWS S3 signature and encoding fixtures passed")
