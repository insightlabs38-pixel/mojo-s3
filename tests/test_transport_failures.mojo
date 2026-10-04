from std.collections import List
from std.os import getenv
from std.testing import assert_equal, assert_true
from mojo_s3.client import S3Store
from mojo_s3.config import S3Config
from mojo_s3.signing import Credentials
from mojo_s3.protocol import Field, get_header
from mojo_s3.http import CurlTransport
from mojo_s3.multipart import complete, CompletedPart


def main() raises:
    var config = S3Config(
        getenv("S3_FAULT_ENDPOINT", "http://127.0.0.1:18081"),
        "us-east-1",
        Credentials("fixture", "fixture", ""),
        False,
        "20261004T000000Z",
        3,
        0,
    )
    var store = S3Store(config)
    var response = store.request(
        "GET", "bucket", "retry", List[Field](), List[Field](), List[UInt8]()
    )
    assert_equal(get_header(response.headers, "x-attempts"), "3")
    assert_true(not store.last_error)
    response = store.request(
        "GET", "bucket", "reset", List[Field](), List[Field](), List[UInt8]()
    )
    assert_equal(get_header(response.headers, "x-attempts"), "2")
    var reuse = store.request(
        "GET", "bucket", "reuse-1", List[Field](), List[Field](), List[UInt8]()
    )
    var reuse_next = store.request(
        "GET", "bucket", "reuse-2", List[Field](), List[Field](), List[UInt8]()
    )
    assert_equal(
        get_header(reuse.headers, "x-client-port"),
        get_header(reuse_next.headers, "x-client-port"),
    )
    var preserved = store.request(
        "GET",
        "bucket",
        "a//../b%2F",
        List[Field](),
        List[Field](),
        List[UInt8](),
    )
    assert_equal(
        get_header(preserved.headers, "x-request-path"), "/bucket/a//../b%252F"
    )
    var failed = False
    try:
        _ = store.get("bucket", "denied")
    except:
        failed = True
    assert_true(failed)
    assert_equal(store.last_error.value().code, "AccessDenied")
    assert_equal(store.last_error.value().request_id, "1")
    var tiny = S3Store(config, CurlTransport(1000, 1000, 16))
    failed = False
    try:
        _ = tiny.get("bucket", "overflow")
    except:
        failed = True
    assert_true(failed)
    assert_equal(tiny.transport.last_code, 23)
    failed = False
    try:
        _ = store.get("bucket", "redirect")
    except:
        failed = True
    assert_true(failed)
    assert_equal(store.last_error.value().status, 302)
    var timeout_config = config.copy()
    timeout_config.max_attempts = 1
    var timed = S3Store(timeout_config, CurlTransport(25, 25))
    failed = False
    try:
        _ = timed.get("bucket", "slow")
    except:
        failed = True
    assert_true(failed)
    assert_equal(timed.last_error.value().category, "Timeout")
    var parts: List[CompletedPart] = [CompletedPart(1, '"etag"')]
    failed = False
    try:
        _ = complete(store, "bucket", "complete", "upload", parts)
    except:
        failed = True
    assert_true(failed)
    assert_equal(store.last_error.value().code, "InternalError")
    assert_equal(store.last_error.value().category, "ServerFailure")
    failed = False
    try:
        _ = store.request(
            "POST",
            "bucket",
            "non-idempotent",
            List[Field](),
            List[Field](),
            List[UInt8](),
            False,
        )
    except:
        failed = True
    assert_true(failed)
    assert_equal(store.last_error.value().status, 503)
    assert_equal(store.last_error.value().request_id, "1")
    print(
        "503 recovery, reset recovery, permanent denial, buffer limits, embedded 200 error, and unsafe-operation retry suppression passed"
    )
