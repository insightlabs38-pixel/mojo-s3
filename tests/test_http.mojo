from std.collections import List
from std.os import getenv
from std.testing import assert_equal
from mojo_s3.http import CurlTransport, HttpRequest
from mojo_s3.protocol import Field


def main() raises:
    var transport = CurlTransport()
    var headers = List[Field]()
    var data = List[UInt8]()
    var response = transport.send(
        HttpRequest(
            "GET",
            getenv("HTTP_TEST_URL", "http://127.0.0.1:18080/"),
            headers^,
            data^,
        )
    )
    assert_equal(response.status, 200)
    print("native HTTP passed", len(response.body))
