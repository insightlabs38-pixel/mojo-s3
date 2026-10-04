from std.collections import List
from std.os import getenv
from std.testing import assert_equal, assert_true
from mojo_s3.client import S3Store
from mojo_s3.crypto import random_token
from mojo_s3.config import S3Config, utc_timestamp
from mojo_s3.crypto import bytes_of, sha256_hex
from mojo_s3.http import CurlTransport, HttpRequest
from mojo_s3.protocol import Field, uri_encode, get_header
from mojo_s3.signing import Credentials
from contract import run_contract


def main() raises:
    var config = S3Config.from_env()
    var store = S3Store(config)
    var bucket = getenv("S3_TEST_BUCKET")
    if not bucket:
        raise Error("S3_TEST_BUCKET is required; use an isolated test bucket")
    var prefix = "mojo-contract-" + utc_timestamp() + "-" + random_token() + "/"
    run_contract(store, bucket, prefix)
    var transport = CurlTransport()
    var key = prefix + "presigned space+%é"
    var url = store.presign("PUT", bucket, key)
    var content = bytes_of("native presigned upload")
    try:
        var response = transport.send(
            HttpRequest("PUT", url, List[Field](), content.copy())
        )
        assert_equal(response.status, 200)
        url = store.presign("GET", bucket, key)
        response = transport.send(
            HttpRequest("GET", url, List[Field](), List[UInt8]())
        )
        assert_equal(response.status, 200)
        assert_equal(sha256_hex(response.body), sha256_hex(content))
        response = transport.send(
            HttpRequest(
                "GET", url + "&tampered=yes", List[Field](), List[UInt8]()
            )
        )
        assert_true(response.status == 403 or response.status == 400)
        var bad_path = url.replace(
            uri_encode(key, True), uri_encode(key + "-changed", True)
        )
        response = transport.send(
            HttpRequest("GET", bad_path, List[Field](), List[UInt8]())
        )
        assert_true(response.status == 403 or response.status == 400)
        var signature_at = url.find("X-Amz-Signature=") + 16
        var bad_sig = (
            String(url[byte=0:signature_at])
            + ("0" if url.as_bytes()[signature_at] != 48 else "1")
            + String(url[byte = signature_at + 1 :])
        )
        response = transport.send(
            HttpRequest("GET", bad_sig, List[Field](), List[UInt8]())
        )
        assert_true(response.status == 403 or response.status == 400)
        var constraints: List[Field] = [
            Field("content-type", "text/plain"),
            Field("x-amz-meta-note", "constrained"),
        ]
        var signed_put = store.presign("PUT", bucket, key, 900, constraints)
        var bad_headers: List[Field] = [
            Field("content-type", "text/plain"),
            Field("x-amz-meta-note", "changed"),
        ]
        response = transport.send(
            HttpRequest("PUT", signed_put, bad_headers^, content.copy())
        )
        assert_true(response.status == 403 or response.status == 400)
        response = transport.send(
            HttpRequest("PUT", signed_put, constraints^, content.copy())
        )
        assert_equal(response.status, 200)
        var constrained_head = store.head(bucket, key)
        assert_equal(
            get_header(constrained_head.metadata, "note"), "constrained"
        )
        var old = config.copy()
        old.fixed_timestamp = "20000101T000000Z"
        var expired_store = S3Store(old)
        response = transport.send(
            HttpRequest(
                "GET",
                expired_store.presign("GET", bucket, key, 1),
                List[Field](),
                List[UInt8](),
            )
        )
        assert_true(response.status == 403 or response.status == 400)
        var wrong = config.copy()
        wrong.credentials = Credentials(
            config.credentials.access_key,
            "deliberately-invalid-test-secret",
            config.credentials.session_token,
        )
        var wrong_store = S3Store(wrong)
        var rejected = False
        try:
            _ = wrong_store.get(bucket, key)
        except:
            rejected = True
        assert_true(rejected)
        assert_true(Bool(wrong_store.last_error))
        assert_equal(
            wrong_store.last_error.value().category, "SignatureMismatch"
        )
    except e:
        store.delete(bucket, key)
        raise e^
    store.delete(bucket, key)
    print(
        "presigned GET/PUT, query tampering, expiry, and wrong-secret rejection passed"
    )
