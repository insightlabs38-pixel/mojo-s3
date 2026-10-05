from std.os import getenv
from std.collections import List
from std.testing import assert_true, assert_equal
from mojo_s3 import (
    S3Store,
    S3Config,
    PutOptions,
    ReadOptions,
    Conditions,
    CopyOptions,
    ObjectIdentifier,
)
from mojo_s3.crypto import random_token, bytes_of
from mojo_s3.protocol import Field


def main() raises:
    var bucket = getenv("S3_TEST_BUCKET")
    if not bucket:
        raise Error("Set an isolated existing bucket")
    var store = S3Store(S3Config.from_env())
    assert_true(store.bucket_exists(bucket))
    var prefix = "mojo-phase2/" + random_token() + "/"
    var key = prefix + "source +%é"
    var copy_key = prefix + "copied"
    var replacement = prefix + "replaced"
    try:
        var options = PutOptions("text/plain")
        options.metadata.append(Field("fixture", "copied"))
        var uploaded = store.put(
            bucket, key, bytes_of("source-content"), options
        )
        assert_true(Bool(uploaded.etag))
        var matched = store.get(
            bucket,
            key,
            ReadOptions(conditions=Conditions(if_match=uploaded.etag)),
        )
        assert_equal(len(matched.data), 14)
        var failed = False
        try:
            _ = store.get(
                bucket,
                key,
                ReadOptions(conditions=Conditions(if_match='"wrong-etag"')),
            )
        except:
            failed = True
        assert_true(failed)
        assert_true(Bool(store.last_error))
        assert_equal(store.last_error.value().category, "PreconditionFailed")
        _ = store.copy_object(bucket, key, bucket, copy_key)
        assert_equal(store.get(bucket, copy_key).data, matched.data)
        assert_equal(store.head(bucket, copy_key).metadata[0].value, "copied")
        var replace_options = PutOptions("application/test")
        replace_options.metadata.append(Field("fixture", "replaced"))
        _ = store.copy_object(
            bucket,
            key,
            bucket,
            replacement,
            CopyOptions(
                metadata_directive="REPLACE", destination=replace_options
            ),
        )
        assert_equal(
            store.head(bucket, replacement).content_type, "application/test"
        )
        var objects: List[ObjectIdentifier] = [
            ObjectIdentifier(copy_key, ""),
            ObjectIdentifier(replacement, ""),
        ]
        var deleted = store.delete_objects(bucket, objects)
        assert_true(deleted.all_succeeded())
        assert_equal(len(deleted.deleted), 2)
        assert_true(not store.exists(bucket, copy_key))
    finally:
        for name in [key, copy_key, replacement]:
            store.delete(bucket, name)
    print(
        "HeadBucket, conditional GET, encoded copy/metadata and batch delete passed"
    )
