from std.os import getenv
from std.testing import assert_equal, assert_true, assert_false
from mojo_s3.client import S3Store
from mojo_s3.config import S3Config
from mojo_s3.concurrent import concurrent_multipart_upload_file
from mojo_s3.crypto import random_token
from mojo_s3.files import NativeFile, hash_file


def main() raises:
    var store = S3Store(S3Config.from_env())
    var bucket = getenv("S3_TEST_BUCKET")
    var source = getenv("S3_STREAM_SOURCE")
    var destination = getenv("S3_STREAM_DESTINATION")
    var key = "mojo-concurrent-" + random_token()
    try:
        for workers in [1, 2, 4, 8]:
            _ = concurrent_multipart_upload_file(
                store, bucket, key, source, workers, 5 * 1024 * 1024
            )
            _ = store.download_file(bucket, key, destination)
            var original = NativeFile(source)
            var downloaded = NativeFile(destination)
            assert_equal(hash_file(original), hash_file(downloaded))
        var failed = False
        try:
            _ = concurrent_multipart_upload_file(
                store,
                bucket,
                key + "-fail",
                source,
                4,
                5 * 1024 * 1024,
                _fail_after=1,
            )
        except:
            failed = True
        assert_true(failed)
        assert_false(store.exists(bucket, key + "-fail"))
    except e:
        store.delete(bucket, key)
        raise e^
    store.delete(bucket, key)
    print(
        "native pthread multipart: 1/2/4/8 workers hash-match; partial launch failure joined and aborted"
    )
