from std.os import getenv
from std.testing import assert_equal, assert_true
from std.collections import List
from mojo_s3 import S3Store, S3Config, PutOptions, CopyOptions, Conditions
from mojo_s3.protocol import Field
from mojo_s3.crypto import random_token, bytes_of
from mojo_s3.files import NativeFile, hash_file
from mojo_s3.multipart import (
    initiate,
    abort,
    complete,
    upload_part_file,
    CompletedPart,
)
from mojo_s3.multipart_plan import plan_multipart
from mojo_s3.multipart_inspection import (
    PartsPaginator,
    MultipartUploadsPaginator,
    list_parts,
)
from mojo_s3.multipart_copy import multipart_copy_object
from mojo_s3.tagging import (
    get_object_tagging,
    put_object_tagging,
    delete_object_tagging,
)


def main() raises:
    var store = S3Store(S3Config.from_env())
    var bucket = getenv("S3_TEST_BUCKET")
    var source = NativeFile(getenv("S3_STREAM_SOURCE"))
    var prefix = "mojo-multipart-extra/" + random_token() + "/"
    var key = prefix + "source + % 雪?"
    var pending = prefix + "pending"
    var copied = prefix + "copy"
    var options = PutOptions("application/octet-stream")
    options.cache_control = "max-age=60"
    options.metadata.append(Field("fixture", "preserved"))
    var first_id = initiate(store, bucket, key, options)
    var second_id = ""
    try:
        # The pinned MinIO backend's prefix/max-uploads/order deviations is recorded
        # independently. Exercise its supported single-upload all-uploads subset only in this
        # explicitly isolated fixture bucket; strict pagination has fault fixtures.
        var listings = MultipartUploadsPaginator(bucket, "", 1000)
        var outstanding = 0
        while not listings.done:
            outstanding += len(listings.next_page(store).uploads)
        assert_equal(outstanding, 1)
        second_id = initiate(store, bucket, pending)
        var plan = plan_multipart(Int64(source.length()), 5 * 1024 * 1024)
        var completed = List[CompletedPart]()
        for number in range(1, plan.part_count + 1):
            completed.append(
                upload_part_file(
                    store,
                    bucket,
                    key,
                    first_id,
                    number,
                    source,
                    plan.offset(number),
                    plan.length(number),
                )
            )
        var parts = PartsPaginator(bucket, key, first_id, 2)
        var bytes = Int64(0)
        var count = 0
        while not parts.done:
            var page = parts.next_page(store)
            for part in page.parts:
                count += 1
                assert_equal(part.number, count)
                assert_equal(part.etag, completed[count - 1].etag)
                bytes += part.size_bytes
        assert_equal(count, plan.part_count)
        assert_equal(bytes, plan.size_bytes)
        _ = complete(store, bucket, key, first_id, completed)
        first_id = ""
        var tags: List[Field] = [
            Field("reserved + /", "a = +"),
            Field("empty", ""),
        ]
        put_object_tagging(store, bucket, key, tags)
        assert_equal(len(get_object_tagging(store, bucket, key)), 2)
        _ = multipart_copy_object(
            store, bucket, key, bucket, copied, CopyOptions(), 5 * 1024 * 1024
        )
        var destination = getenv("S3_STREAM_DESTINATION")
        _ = store.download_file(bucket, copied, destination)
        var copy_file = NativeFile(destination)
        assert_equal(hash_file(copy_file), hash_file(source))
        assert_equal(len(get_object_tagging(store, bucket, copied)), 2)
        assert_equal(store.head(bucket, copied).metadata[0].value, "preserved")
        _ = multipart_copy_object(
            store,
            bucket,
            key,
            bucket,
            copied,
            CopyOptions(tagging_directive="REPLACE"),
            5 * 1024 * 1024,
        )
        assert_equal(len(get_object_tagging(store, bucket, copied)), 0)
        var replaced = PutOptions()
        replaced.tags = [Field("replacement", "yes")]
        _ = store.copy_object(
            bucket,
            key,
            bucket,
            copied,
            CopyOptions(destination=replaced, tagging_directive="REPLACE"),
        )
        assert_equal(
            get_object_tagging(store, bucket, copied)[0].name, "replacement"
        )
        delete_object_tagging(store, bucket, copied)
        assert_equal(len(get_object_tagging(store, bucket, copied)), 0)
        var mismatch = CopyOptions()
        mismatch.source_conditions = Conditions(if_match="wrong-etag")
        var refused = False
        try:
            _ = multipart_copy_object(
                store, bucket, key, bucket, copied, mismatch
            )
        except:
            refused = True
        assert_true(refused)
        assert_equal(store.last_error.value().status, 412)
        abort(store, bucket, pending, second_id)
        second_id = ""
    finally:
        if first_id:
            abort(store, bucket, key, first_id)
        if second_id:
            abort(store, bucket, pending, second_id)
        store.delete(bucket, key)
        store.delete(bucket, copied)
    print(
        "Streamed file parts, bounded multipart listings, encoded multipart copy, source conditions, metadata/tags and cleanup passed"
    )
