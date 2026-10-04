from std.testing import assert_equal, assert_true
from std.collections import List
from mojo_s3.protocol import (
    Field,
    address,
    uri_encode,
    canonical_query,
    normalize_space,
)
from mojo_s3.client import decode_key, decimal
from mojo_s3.objects import ObjectRange
from mojo_s3.errors import parse_s3_error
from mojo_s3.http import HttpResponse
from mojo_s3.crypto import bytes_of


def main() raises:
    assert_equal(normalize_space("  é\t雪  "), "é 雪")
    assert_equal(decode_key("a%2Fb%25+c%C3%A9"), "a/b%+cé")
    assert_equal(uri_encode("/./../a//", True), "/./../a//")
    assert_equal(ObjectRange(0).header(), "bytes=0-")
    assert_equal(ObjectRange(0, 0).header(), "bytes=0-0")
    assert_equal(decimal("9223372036854775807"), 9223372036854775807)
    var failure = False
    try:
        _ = decimal("9223372036854775808")
    except:
        failure = True
    assert_true(failure)
    for bad in [
        "http://",
        "ftp://host",
        "https://user:pass@host",
        "http://host?x=1",
        "http://ho st",
    ]:
        failure = False
        try:
            _ = address(bad, "bucket", "x")
        except:
            failure = True
        assert_true(failure)
    for bad in ["a\r\nb", "bad\x00value", "bad\x01value"]:
        failure = False
        try:
            _ = normalize_space(bad)
        except:
            failure = True
        assert_true(failure)
    var response = HttpResponse(
        403,
        List[Field](),
        bytes_of(
            "<Error><Code>SignatureDoesNotMatch</Code><Message>bad &amp; wrong</Message><RequestId>req</RequestId><HostId>host</HostId><Resource>/b/k</Resource></Error>"
        ),
    )
    var error = parse_s3_error(response)
    assert_equal(error.category, "SignatureMismatch")
    assert_equal(error.message, "bad & wrong")
    assert_equal(error.request_id, "req")
    response = HttpResponse(503, List[Field](), bytes_of("upstream failure"))
    assert_equal(parse_s3_error(response).category, "ServerFailure")
    print(
        "protocol validation, range, integer overflow, and S3 error fixtures passed"
    )
