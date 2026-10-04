from std.collections import List
from std.os import getenv
from std.testing import assert_equal, assert_true, assert_false
from mojo_s3.client import S3Store
from mojo_s3.crypto import random_token
from mojo_s3.config import S3Config, utc_timestamp
from mojo_s3.files import NativeFile, hash_file
from mojo_s3.crypto import bytes_of
from mojo_s3.multipart import (
    initiate,
    upload_part,
    complete,
    abort,
    multipart_upload_file,
    CompletedPart,
)


def main() raises:
    var store = S3Store(S3Config.from_env())
    var bucket = getenv("S3_TEST_BUCKET")
    var source = getenv("S3_STREAM_SOURCE")
    var destination = getenv("S3_STREAM_DESTINATION")
    var key = "mojo-multipart-" + utc_timestamp() + "-" + random_token()
    try:
        var result = multipart_upload_file(
            store, bucket, key, source, 5 * 1024 * 1024
        )
        assert_true(Bool(result.etag))
        _ = store.download_file(bucket, key, destination)
        var original = NativeFile(source)
        var downloaded = NativeFile(destination)
        assert_equal(hash_file(original), hash_file(downloaded))
        var upload_id = initiate(store, bucket, key + "-abort")
        _ = upload_part(
            store,
            bucket,
            key + "-abort",
            upload_id,
            1,
            bytes_of("small last part"),
        )
        abort(store, bucket, key + "-abort", upload_id)
        assert_false(store.exists(bucket, key + "-abort"))
        var failed = False
        try:
            _ = upload_part(
                store,
                bucket,
                key + "-abort",
                upload_id,
                1,
                bytes_of("stale upload"),
            )
        except:
            failed = True
        assert_true(failed)
        upload_id = initiate(store, bucket, key + "-single")
        var parts = List[CompletedPart]()
        parts.append(
            upload_part(
                store,
                bucket,
                key + "-single",
                upload_id,
                1,
                bytes_of("one final part"),
            )
        )
        _ = complete(store, bucket, key + "-single", upload_id, parts)
        assert_equal(len(store.get(bucket, key + "-single").data), 14)
        store.delete(bucket, key + "-single")
    except e:
        store.delete(bucket, key)
        raise e^
    store.delete(bucket, key)
    print(
        "multipart 7-part uneven-tail hash roundtrip, abort, stale part, and one-part completion passed"
    )
