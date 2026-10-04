from std.os import getenv
from std.testing import assert_true, assert_equal
from mojo_s3.client import S3Store
from mojo_s3.config import S3Config
from mojo_s3.crypto import bytes_of, random_token


def main() raises:
    var config = S3Config.from_env()
    config.request_checksums = True
    var store = S3Store(config)
    var bucket = getenv("S3_TEST_BUCKET")
    var key = "mojo-checksum-" + random_token()
    try:
        _ = store.put(bucket, key, bytes_of("full-object SHA256 fixture"))
        var result = store.get(bucket, key)
        assert_true(result.metadata.checksum_verified)
        assert_equal(result.metadata.checksum_algorithm, "sha256")
        _ = store.upload_file(bucket, key, getenv("S3_STREAM_SOURCE"))
        var metadata = store.download_file(
            bucket, key, getenv("S3_STREAM_DESTINATION")
        )
        assert_true(metadata.checksum_verified)
    except e:
        store.delete(bucket, key)
        raise e^
    store.delete(bucket, key)
    print(
        "live negotiated full-object SHA256 checksums verified for buffered and streamed transfers"
    )
