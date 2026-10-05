from std.os import getenv
from std.testing import assert_true, assert_equal
from mojo_s3.client import S3Store
from mojo_s3.config import S3Config
from mojo_s3.crypto import bytes_of, random_token


def main() raises:
    for algorithm in ["sha256", "sha1", "crc32", "crc32c"]:
        var config = S3Config.from_env()
        config.request_checksums = True
        config.checksum_algorithm = algorithm
        var store = S3Store(config)
        var bucket = getenv("S3_TEST_BUCKET")
        var key = "mojo-checksum-" + random_token()
        try:
            _ = store.put(bucket, key, bytes_of("full-object checksum fixture"))
            var result = store.get(bucket, key)
            assert_true(result.metadata.checksum_verified)
            assert_equal(result.metadata.checksum_algorithm, algorithm)
            _ = store.upload_file(bucket, key, getenv("S3_STREAM_SOURCE"))
            var metadata = store.download_file(
                bucket, key, getenv("S3_STREAM_DESTINATION")
            )
            assert_true(metadata.checksum_verified)
            assert_equal(metadata.checksum_algorithm, algorithm)
        except e:
            store.delete(bucket, key)
            raise e^
        store.delete(bucket, key)
    print(
        "SHA256, SHA1, CRC32 and CRC32C buffered and streamed checksums verified"
    )
