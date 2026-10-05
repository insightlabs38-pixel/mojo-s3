from std.collections import List
from std.os import getenv
from std.testing import assert_equal, assert_true, assert_false
from mojo_s3.client import S3Store
from mojo_s3.config import S3Config
from mojo_s3.crypto import sha256, base64_encode, bytes_of
from mojo_s3.signing import Credentials
from mojo_s3.files import NativeFile, hash_file


def main() raises:
    assert_equal(
        base64_encode(sha256(bytes_of("abc"))),
        "ungWv48Bz+pBQUDeXa4iI7ADYaOWF3qctBD/YfIAFa0=",
    )
    var config = S3Config(
        getenv("S3_FAULT_ENDPOINT"),
        "us-east-1",
        Credentials("fixture", "fixture", ""),
        False,
        "20261004T000000Z",
        1,
        0,
        True,
    )
    var store = S3Store(config)
    for algorithm in ["sha256", "sha1", "crc32", "crc32c"]:
        var key = "checksum-" + algorithm
        var good = store.get("bucket", key + "-good")
        assert_true(good.metadata.checksum_verified)
        assert_equal(good.metadata.checksum_algorithm, algorithm)
        var composite = store.get("bucket", key + "-composite")
        assert_false(composite.metadata.checksum_verified)
        assert_equal(composite.metadata.checksum_state, "composite")
        var failed = False
        try:
            _ = store.get("bucket", key + "-bad")
        except:
            failed = True
        assert_true(failed)
        assert_equal(store.last_error.value().category, "DataIntegrity")
        var source = getenv("S3_CONCURRENT_SOURCE")
        var original = NativeFile(source)
        var hash = hash_file(original)
        failed = False
        try:
            _ = store.download_file("bucket", key + "-bad", source)
        except:
            failed = True
        assert_true(failed)
        var unchanged = NativeFile(source)
        assert_equal(hash_file(unchanged), hash)
    print(
        "SHA256 Base64, valid checksums, corruption rejection, composite non-validation, and atomic file preservation passed"
    )
