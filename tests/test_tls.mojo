from std.collections import List
from std.os import getenv
from std.testing import assert_equal, assert_true
from mojo_s3.http import CurlTransport, HttpRequest
from mojo_s3.protocol import Field


def main() raises:
    var endpoint = getenv("S3_TLS_ENDPOINT")
    var ca = getenv("S3_TLS_CA")
    var request = HttpRequest("GET", endpoint, List[Field](), List[UInt8]())
    var default_transport = CurlTransport()
    var failed = False
    try:
        _ = default_transport.send(request)
    except:
        failed = True
    assert_true(failed)
    assert_equal(default_transport.last_code, 60)
    var trusted = CurlTransport(1000, 1000, 1024, True, ca)
    assert_equal(trusted.send(request).status, 200)
    var insecure = CurlTransport(1000, 1000, 1024, False)
    assert_equal(insecure.send(request).status, 200)
    print(
        "TLS verification default, custom CA trust, and explicit insecure option passed"
    )
