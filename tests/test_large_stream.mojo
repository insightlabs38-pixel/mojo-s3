from std.os import getenv
from std.testing import assert_equal
from mojo_s3 import S3Store, S3Config
from mojo_s3.concurrent import concurrent_multipart_upload_file


def main() raises:
    var store = S3Store(S3Config.from_env())
    store.transport.timeout_ms = 120000
    var result = concurrent_multipart_upload_file(
        store,
        "fixture",
        "large",
        getenv("S3_STREAM_SOURCE"),
        2,
        atol(getenv("S3_PART_BYTES")),
    )
    assert_equal(result.etag, "fixture-complete")
    print(
        "Large streamed parts with independent wide-offset wire verification passed"
    )
