"""Explicit existing-bucket/prefix qualification. No bucket administration."""
from std.os import getenv
from std.collections import List
from std.testing import assert_true, assert_equal
from mojo_s3 import (
    S3Store,
    S3Config,
    PutOptions,
    TransferManager,
    TransferOptions,
    ObjectIdentifier,
    PartsPaginator,
    MultipartUploadsPaginator,
    multipart_copy_object,
    get_object_tagging,
    put_object_tagging,
    delete_object_tagging,
)
from mojo_s3.crypto import bytes_of, sha256_hex
from mojo_s3.http import CurlTransport, HttpRequest
from mojo_s3.protocol import Field
from mojo_s3.files import NativeFile, hash_file
from mojo_s3.multipart import (
    multipart_upload_file,
    initiate,
    upload_part_file,
    abort,
)
from mojo_s3.concurrent import concurrent_multipart_upload_file
from contract import run_contract


def main() raises:
    var bucket = getenv("S3_AWS_TEST_BUCKET")
    var prefix = getenv("S3_AWS_TEST_PREFIX")
    if (
        getenv("RUN_AWS_S3_INTEGRATION") != "1"
        or getenv("S3_AWS_TEST_AUTHORIZATION") != bucket
        or not bucket
        or not prefix.startswith("mojo-s3-qualification/")
        or not prefix.endswith("/")
    ):
        raise Error(
            "AWS qualification requires explicit existing-bucket authorization and isolated prefix"
        )
    var config = S3Config.from_default()
    config.request_checksums = True
    var store = S3Store(config)
    run_contract(store, bucket, prefix + "contract/")
    var key = prefix + "transfer"
    var copy_key = prefix + "copy"
    var pending_key = prefix + "pending"
    var pending_id = ""
    try:
        store.head_bucket(bucket)
        var transport = CurlTransport()
        var data = bytes_of("native AWS presign fixture")
        var response = transport.send(
            HttpRequest(
                "PUT",
                store.presign("PUT", bucket, key, 60),
                List[Field](),
                data.copy(),
            )
        )
        assert_equal(response.status, 200)
        response = transport.send(
            HttpRequest(
                "GET",
                store.presign("GET", bucket, key, 60),
                List[Field](),
                List[UInt8](),
            )
        )
        assert_equal(response.status, 200)
        assert_equal(sha256_hex(response.body), sha256_hex(data))
        for algorithm in ["sha256", "sha1", "crc32", "crc32c"]:
            store.config.checksum_algorithm = algorithm
            _ = store.put(bucket, key, data)
            assert_true(store.get(bucket, key).metadata.checksum_verified)
        _ = store.copy_object(bucket, key, bucket, copy_key)
        assert_equal(
            sha256_hex(store.get(bucket, copy_key).data), sha256_hex(data)
        )
        var deleted = store.delete_objects(
            bucket, [ObjectIdentifier(copy_key, "")]
        )
        assert_true(deleted.all_succeeded())
        assert_equal(len(deleted.deleted), 1)
        var source = getenv("S3_STREAM_SOURCE")
        var destination = getenv("S3_STREAM_DESTINATION")
        var original = NativeFile(source)
        var expected = hash_file(original)
        _ = store.upload_file(bucket, key, source)
        _ = store.download_file(bucket, key, destination)
        var downloaded = NativeFile(destination)
        assert_equal(hash_file(downloaded), expected)
        _ = multipart_upload_file(store, bucket, key, source, 5 * 1024 * 1024)
        _ = concurrent_multipart_upload_file(
            store, bucket, key, source, 4, 5 * 1024 * 1024
        )
        put_object_tagging(
            store, bucket, key, [Field("qualification", "native")]
        )
        assert_equal(len(get_object_tagging(store, bucket, key)), 1)
        _ = multipart_copy_object(store, bucket, key, bucket, copy_key)
        assert_equal(len(get_object_tagging(store, bucket, copy_key)), 1)
        _ = store.download_file(bucket, copy_key, destination)
        var copied_file = NativeFile(destination)
        assert_equal(hash_file(copied_file), expected)
        delete_object_tagging(store, bucket, copy_key)
        store.delete(bucket, copy_key)
        pending_id = initiate(store, bucket, pending_key)
        _ = upload_part_file(
            store,
            bucket,
            pending_key,
            pending_id,
            1,
            original,
            0,
            Int64(min(original.length(), 5 * 1024 * 1024)),
        )
        var parts = PartsPaginator(bucket, pending_key, pending_id, 1)
        assert_equal(len(parts.next_page(store).parts), 1)
        assert_true(parts.done)
        var uploads = MultipartUploadsPaginator(bucket, prefix, 1)
        var found = False
        while not uploads.done:
            for upload in uploads.next_page(store).uploads:
                if upload.key == pending_key and upload.upload_id == pending_id:
                    found = True
        assert_true(found)
        abort(store, bucket, pending_key, pending_id)
        pending_id = ""
        var manager = TransferManager(
            store^, TransferOptions(1, 5 * 1024 * 1024, 4)
        )
        _ = manager.upload_file(bucket, key, source)
        _ = manager.download_file(bucket, key, destination)
        var ranged = NativeFile(destination)
        assert_equal(hash_file(ranged), expected)
        manager.store.delete(bucket, key)
        print("AWS existing-bucket/prefix qualification passed")
    except e:
        # The runner reports this exact prefix for manual cleanup if denied.
        # Store may have moved into the manager; contract cleanup is independent.
        var cleanup = S3Store(config)
        if pending_id:
            try:
                abort(cleanup, bucket, pending_key, pending_id)
            except:
                print("Orphan multipart upload ID:", pending_id)
        for cleanup_key in [key, copy_key]:
            try:
                cleanup.delete(bucket, cleanup_key)
            except:
                pass  # Preserve the primary failure; runner prints cleanup prefix.
        raise e^
