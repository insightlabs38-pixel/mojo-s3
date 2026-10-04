from std.collections import List
from std.os import getenv
from std.testing import assert_equal, assert_true
from mojo_s3.client import S3Store, decimal
from mojo_s3.config import S3Config
from mojo_s3.concurrent import concurrent_multipart_upload_file
from mojo_s3.protocol import Field, get_header
from mojo_s3.signing import Credentials


def main() raises:
    var config = S3Config(
        getenv("S3_FAULT_ENDPOINT"),
        "us-east-1",
        Credentials("fixture", "fixture", ""),
        False,
        "20261004T000000Z",
        1,
        0,
    )
    var store = S3Store(config)
    var source = getenv("S3_CONCURRENT_SOURCE")
    for key in [
        "concurrent-fail",
        "concurrent-complete-fail",
        "concurrent-launch",
    ]:
        var failed = False
        try:
            _ = concurrent_multipart_upload_file(
                store,
                "bucket",
                key,
                source,
                3,
                5 * 1024 * 1024,
                _fail_after=1 if key == "concurrent-launch" else -1,
            )
        except:
            failed = True
        assert_true(failed)
        if key != "concurrent-launch":
            assert_equal(store.last_error.value().code, "InternalError")
        var stats = store.request(
            "GET", "bucket", key, List[Field](), List[Field](), List[UInt8]()
        )
        assert_equal(get_header(stats.headers, "x-abort"), "1")
        assert_equal(get_header(stats.headers, "x-active-at-abort"), "0")
        var peak = decimal(get_header(stats.headers, "x-peak"))
        assert_true(peak <= 3)
        if key != "concurrent-launch":
            assert_true(peak >= 2)
    print(
        "bounded simultaneous parts, worker error preservation, embedded completion failure, joins-before-abort, and partial launch cleanup passed"
    )
