from std.os import getenv
from std.testing import assert_equal, assert_true
from mojo_s3 import S3Store, S3Config
from mojo_s3.crypto import random_token, bytes_of
from mojo_s3.files import NativeFile, hash_file
from mojo_s3.downloads import concurrent_download_file
from mojo_s3.transfer_control import (
    TransferControl,
    ProgressObserver,
    TransferProgress,
)


struct RecordingObserver(ProgressObserver):
    var last: Int
    var calls: Int

    def __init__(out self):
        self.last = 0
        self.calls = 0

    def on_progress(mut self, progress: TransferProgress) raises:
        assert_true(progress.completed_bytes >= self.last)
        assert_true(progress.completed_bytes <= progress.total_bytes)
        self.last = progress.completed_bytes
        self.calls += 1


def main() raises:
    var bucket = getenv("S3_TEST_BUCKET")
    var source = getenv("S3_STREAM_SOURCE")
    var destination = getenv("S3_STREAM_DESTINATION")
    if not bucket or not source or not destination:
        raise Error("Set isolated bucket and fixture paths")
    var store = S3Store(S3Config.from_env())
    var source_file = NativeFile(source)
    var expected = hash_file(source_file)
    var key = "mojo-downloads/" + random_token()
    try:
        _ = store.upload_file(bucket, key, source)
        for workers in [1, 2, 4, 8]:
            var control = TransferControl()
            var observer = RecordingObserver()
            var metadata = concurrent_download_file(
                store,
                bucket,
                key,
                destination,
                workers,
                3 * 1024 * 1024 + 1,
                control,
                observer,
            )
            var downloaded = NativeFile(destination)
            assert_equal(hash_file(downloaded), expected)
            assert_equal(observer.last, metadata.size)
            assert_true(observer.calls > 0)
        _ = store.put(bucket, key, bytes_of("small"))
        var small_control = TransferControl()
        var small_observer = RecordingObserver()
        _ = concurrent_download_file(
            store,
            bucket,
            key,
            destination,
            8,
            1024,
            small_control,
            small_observer,
        )
        assert_equal(small_observer.last, 5)
        _ = store.put(bucket, key, bytes_of(""))
        var zero_control = TransferControl()
        var zero_observer = RecordingObserver()
        _ = concurrent_download_file(
            store,
            bucket,
            key,
            destination,
            8,
            1024,
            zero_control,
            zero_observer,
        )
        assert_equal(zero_observer.last, 0)
    finally:
        store.delete(bucket, key)
    print(
        "Concurrent downloads: 1/2/4/8 workers, odd tails, small/empty and coordinator progress passed"
    )
