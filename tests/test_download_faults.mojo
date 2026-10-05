from std.os import getenv
from std.memory import Pointer
from std.testing import assert_equal, assert_true
from mojo_s3 import S3Store, S3Config
from mojo_s3.files import NativeFile, hash_file
from mojo_s3.downloads import concurrent_download_file
from mojo_s3.transfer_control import (
    TransferControl,
    TransferProgress,
    ProgressObserver,
    NoProgress,
)


struct CancelObserver(ProgressObserver):
    var control: Pointer[TransferControl, MutUntrackedOrigin]
    var fail: Bool

    def __init__(out self, mut control: TransferControl, fail: Bool):
        self.control = Pointer(to=control).unsafe_origin_cast[
            MutUntrackedOrigin
        ]()
        self.fail = fail

    def on_progress(mut self, progress: TransferProgress) raises:
        if self.fail:
            raise Error("Intentional observer failure")
        self.control[].cancel()


def main() raises:
    var destination = getenv("S3_DOWNLOAD_DESTINATION")
    var existing = NativeFile(destination)
    var expected = hash_file(existing)
    var store = S3Store(S3Config.from_env())
    for key in ["denied", "range", "truncated", "checksum"]:
        var control = TransferControl()
        var observer = NoProgress()
        var failed = False
        try:
            _ = concurrent_download_file(
                store, "bucket", key, destination, 4, 1024, control, observer
            )
        except:
            failed = True
        assert_true(failed)
        var preserved = NativeFile(destination)
        assert_equal(hash_file(preserved), expected)
    for mode in range(4):
        var control = TransferControl()
        var observer = CancelObserver(control, mode == 1)
        var failed = False
        if mode == 2:
            control.cancel()
        try:
            _ = concurrent_download_file(
                store,
                "bucket",
                "valid",
                destination,
                4,
                1024,
                control,
                observer,
                fail_after=1 if mode == 3 else -1,
            )
        except:
            failed = True
        assert_true(failed)
        var preserved = NativeFile(destination)
        assert_equal(hash_file(preserved), expected)
    var control = TransferControl()
    var observer = NoProgress()
    var failed = False
    try:
        _ = concurrent_download_file(
            store,
            "bucket",
            "valid",
            destination,
            2,
            1024,
            control,
            observer,
            _write_fd_override=existing.fd,
        )
    except:
        failed = True
    assert_true(failed)
    var preserved = NativeFile(destination)
    assert_equal(hash_file(preserved), expected)
    var success_control = TransferControl()
    var success_observer = NoProgress()
    var success = concurrent_download_file(
        store,
        "bucket",
        "valid",
        destination + "-success",
        4,
        1024,
        success_control,
        success_observer,
    )
    assert_true(success.checksum_verified)
    assert_equal(success_control.progress().completed_bytes, 7169)
    _ = existing
    print(
        "Concurrent download errors/cancellation/callback/launch/write faults preserve destination"
    )
