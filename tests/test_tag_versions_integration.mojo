"""Use a preconfigured versioned fixture bucket; never change bucket settings."""
from std.os import getenv
from std.testing import assert_equal, assert_true
from mojo_s3 import (
    S3Store,
    S3Config,
    Field,
    ReadOptions,
    CopyOptions,
    get_object_tagging,
    put_object_tagging,
    delete_object_tagging,
    multipart_copy_object,
)
from mojo_s3.crypto import bytes_of, random_token


def main() raises:
    var store = S3Store(S3Config.from_env())
    var bucket = getenv("S3_VERSIONED_TEST_BUCKET")
    if not bucket:
        raise Error("Provide an authorized preconfigured versioned bucket")
    var key = "mojo-version-tags/" + random_token()
    var copied = key + "-copy"
    var first = store.put(bucket, key, bytes_of("first"))
    var second = store.put(bucket, key, bytes_of("second"))
    var copy_version = ""
    assert_true(first.version_id != "" and second.version_id != "")
    try:
        put_object_tagging(
            store, bucket, key, [Field("revision", "one")], first.version_id
        )
        put_object_tagging(
            store, bucket, key, [Field("revision", "two")], second.version_id
        )
        assert_equal(
            get_object_tagging(store, bucket, key, first.version_id)[0].value,
            "one",
        )
        assert_equal(
            get_object_tagging(store, bucket, key, second.version_id)[0].value,
            "two",
        )
        var result = multipart_copy_object(
            store,
            bucket,
            key,
            bucket,
            copied,
            CopyOptions(source_version_id=first.version_id),
        )
        copy_version = result.version_id
        assert_equal(len(store.get(bucket, copied).data), 5)
        assert_equal(get_object_tagging(store, bucket, copied)[0].value, "one")
        delete_object_tagging(store, bucket, key, first.version_id)
        assert_equal(
            len(get_object_tagging(store, bucket, key, first.version_id)), 0
        )
        assert_equal(
            get_object_tagging(store, bucket, key, second.version_id)[0].value,
            "two",
        )
    finally:
        store.delete(bucket, key, ReadOptions(first.version_id))
        store.delete(bucket, key, ReadOptions(second.version_id))
        if copy_version:
            store.delete(bucket, copied, ReadOptions(copy_version))
    print(
        "Explicit source-version multipart copy and isolated version tag mutations passed"
    )
