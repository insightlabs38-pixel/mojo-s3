from std.os import getenv
from std.testing import assert_true, assert_equal
from mojo_s3 import S3Store, S3Config, ReadOptions, CopyOptions
from mojo_s3.crypto import random_token, bytes_of


def main() raises:
    if getenv("S3_VERSIONED_FIXTURE") != "1":
        raise Error(
            "Requires an explicitly enabled, isolated versioned fixture"
        )
    var bucket = getenv("S3_TEST_BUCKET")
    var store = S3Store(S3Config.from_env())
    var key = "mojo-versions/" + random_token()
    var copied = key + "-copy"
    var first = store.put(bucket, key, bytes_of("first"))
    var second = store.put(bucket, key, bytes_of("second"))
    assert_true(Bool(first.version_id))
    assert_true(first.version_id != second.version_id)
    assert_equal(
        store.get(bucket, key, ReadOptions(first.version_id)).data,
        bytes_of("first"),
    )
    assert_equal(
        store.head(bucket, key, ReadOptions(first.version_id)).version_id,
        first.version_id,
    )
    var copy = store.copy_object(
        bucket,
        key,
        bucket,
        copied,
        CopyOptions(source_version_id=first.version_id),
    )
    assert_equal(store.get(bucket, copied).data, bytes_of("first"))
    store.delete(bucket, key, ReadOptions(first.version_id))
    assert_equal(store.get(bucket, key).data, bytes_of("second"))
    store.delete(bucket, key, ReadOptions(second.version_id))
    store.delete(bucket, copied, ReadOptions(copy.version_id))
    print("Opaque version GET/HEAD/DELETE and copy source version passed")
