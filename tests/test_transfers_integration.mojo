from std.os import getenv
from std.testing import assert_equal, assert_true
from std.ffi import external_call
from mojo_s3 import S3Store, S3Config, PutOptions
from mojo_s3.crypto import random_token
from mojo_s3.files import NativeFile, hash_file
from mojo_s3.transfers import TransferOptions, TransferManager


def main() raises:
    var bucket = getenv("S3_TEST_BUCKET")
    var source = getenv("S3_STREAM_SOURCE")
    var destination = (
        getenv("S3_STREAM_DESTINATION") + ".manager-" + random_token()
    )
    if not bucket or not source or not getenv("S3_STREAM_DESTINATION"):
        raise Error("Configure isolated transfer fixture paths and bucket")
    var file = NativeFile(source)
    var expected = hash_file(file)
    var length = file.length()
    for mode in range(3):
        var store = S3Store(S3Config.from_env())
        var options = TransferOptions(
            multipart_threshold=length + 1 if mode == 0 else 0,
            workers=1 if mode == 1 else 4,
        )
        var manager = TransferManager(store^, options)
        var key = "mojo-manager-" + random_token()
        try:
            var uploaded = manager.upload_file(
                bucket, key, source, PutOptions("application/octet-stream")
            )
            assert_true(Bool(uploaded.etag))
            var metadata = manager.download_file(bucket, key, destination)
            assert_equal(metadata.size, length)
            var downloaded = NativeFile(destination)
            assert_equal(hash_file(downloaded), expected)
        finally:
            manager.store.delete(bucket, key)
            _ = external_call["unlink", Int32](destination.as_c_string_span())
    print(
        "Transfer manager streamed/sequential/concurrent file roundtrips passed"
    )
