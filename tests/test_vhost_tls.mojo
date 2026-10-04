from std.collections import List
from std.os import getenv
from std.testing import assert_equal, assert_true
from mojo_s3.client import S3Store
from mojo_s3.config import S3Config
from mojo_s3.crypto import bytes_of, random_token, sha256_hex
from mojo_s3.http import CurlTransport, HttpRequest
from mojo_s3.objects import ListOptions, ObjectRange
from mojo_s3.protocol import Field
from mojo_s3.concurrent import concurrent_multipart_upload_file


def main() raises:
    var config = S3Config.from_env()
    config.virtual_host = True
    var ca = getenv("S3_CA_BUNDLE")
    var store = S3Store(
        config, CurlTransport(30000, 5000, 64 * 1024 * 1024, True, ca)
    )
    var transport = CurlTransport(30000, 5000, 64 * 1024 * 1024, True, ca)
    var bucket = getenv("S3_TEST_BUCKET")
    var prefix = "mojo-vhost-" + random_token() + "/"
    var key = prefix + "space+%é"
    var content = bytes_of("TLS virtual-host fixture")
    try:
        _ = store.put(bucket, key, content)
        assert_equal(
            sha256_hex(store.get(bucket, key).data), sha256_hex(content)
        )
        assert_equal(store.head(bucket, key).size, len(content))
        assert_equal(len(store.list(bucket, ListOptions(prefix)).objects), 1)
        assert_equal(
            len(store.get_range(bucket, key, ObjectRange(1, 4)).data), 4
        )
        var url = store.presign("GET", bucket, key, 60)
        var response = transport.send(
            HttpRequest("GET", url, List[Field](), List[UInt8]())
        )
        assert_equal(response.status, 200)
        assert_equal(sha256_hex(response.body), sha256_hex(content))
        _ = concurrent_multipart_upload_file(
            store, bucket, key, getenv("S3_STREAM_SOURCE"), 3, 5 * 1024 * 1024
        )
        _ = store.download_file(bucket, key, getenv("S3_STREAM_DESTINATION"))
    except e:
        store.delete(bucket, key)
        raise e^
    store.delete(bucket, key)
    assert_true(not store.exists(bucket, key))
    print(
        "live virtual-host TLS CRUD/list/range/presign/concurrent multipart with explicit CA trust passed"
    )
