from std.os import getenv
from std.testing import assert_equal, assert_true
from mojo_s3.crypto import random_token
from mojo_s3.config import S3Config, utc_timestamp
from mojo_s3.client import S3Store
from mojo_s3.files import NativeFile, hash_file


def main() raises:
    var source = getenv("S3_STREAM_SOURCE")
    var destination = getenv("S3_STREAM_DESTINATION")
    if not source or not destination:
        raise Error("S3_STREAM_SOURCE and S3_STREAM_DESTINATION required")
    var store = S3Store(S3Config.from_env())
    var bucket = getenv("S3_TEST_BUCKET")
    var key = "mojo-stream-" + utc_timestamp() + "-" + random_token()
    try:
        var result = store.upload_file(bucket, key, source)
        assert_true(Bool(result.etag))
        var metadata = store.download_file(bucket, key, destination)
        var original = NativeFile(source)
        var downloaded = NativeFile(destination)
        assert_equal(metadata.size, original.length())
        assert_equal(hash_file(downloaded), hash_file(original))
        var failed = False
        try:
            _ = store.download_file(bucket, key + "-missing", destination)
        except:
            failed = True
        assert_true(failed)
        var unchanged = NativeFile(destination)
        assert_equal(hash_file(unchanged), hash_file(original))
    except e:
        store.delete(bucket, key)
        raise e^
    store.delete(bucket, key)
    print(
        "streamed upload/download hash match and atomic failure preservation passed"
    )
