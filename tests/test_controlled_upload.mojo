from std.os import getenv
from std.testing import assert_equal, assert_true
from mojo_s3 import S3Store, S3Config, PutOptions
from mojo_s3.concurrent import controlled_multipart_upload_file
from mojo_s3.transfer_control import (
    TransferControl,
    TransferProgress,
    ProgressObserver,
)


struct Observer(ProgressObserver):
    var requested: Bool
    var mode: Int
    var previous: Int

    def __init__(out self, mode: Int):
        self.requested = False
        self.mode = mode
        self.previous = 0

    def on_progress(mut self, progress: TransferProgress) raises:
        assert_true(progress.completed_bytes >= self.previous)
        assert_true(progress.completed_bytes <= progress.total_bytes)
        self.previous = progress.completed_bytes
        if self.mode == 1:
            self.requested = True
        elif self.mode == 5:
            self.requested = progress.completed_bytes == progress.total_bytes
        elif self.mode == 2:
            raise Error("Intentional upload observer failure")

    def cancel_requested(self) -> Bool:
        return self.requested


def main() raises:
    var store = S3Store(S3Config.from_env())
    var bucket = getenv("S3_TEST_BUCKET")
    for mode in range(6):
        var control = TransferControl()
        var observer = Observer(mode)
        if mode == 3:
            control.cancel()
        var failed = False
        try:
            _ = controlled_multipart_upload_file(
                store,
                bucket,
                "controlled-" + String(mode),
                getenv("S3_STREAM_SOURCE"),
                4,
                5 * 1024 * 1024,
                PutOptions(),
                control,
                observer,
                1 if mode == 4 else -1,
            )
        except:
            failed = True
        assert_equal(failed, mode != 0)
        if not mode:
            assert_equal(
                control.progress().completed_bytes,
                control.progress().total_bytes,
            )
            store.delete(bucket, "controlled-0")
    print(
        "Controlled upload progress, cancellation, observer failure and partial launch passed"
    )
