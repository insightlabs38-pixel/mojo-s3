from std.os import getenv
from std.testing import assert_equal
from mojo_s3.client import S3Store
from mojo_s3.config import S3Config
from mojo_s3.files import NativeFile, hash_file


def main() raises:
    var store = S3Store(S3Config.from_env())
    var bucket = getenv("S3_TEST_BUCKET")
    var prefix = getenv("S3_INTEROP_PREFIX")
    var source = getenv("S3_STREAM_SOURCE")
    var destination = getenv("S3_STREAM_DESTINATION")
    _ = store.download_file(bucket, prefix + "reference", destination)
    var original = NativeFile(source)
    var downloaded = NativeFile(destination)
    assert_equal(hash_file(original), hash_file(downloaded))
    _ = store.upload_file(bucket, prefix + "mojo", source)
    print("reference-client upload verified by native Mojo")
