from std.testing import assert_equal, assert_true
from mojo_s3.transfer_control import (
    TransferControl,
    TransferProgress,
    NoProgress,
)


def main() raises:
    var control = TransferControl()
    control.start(100)
    control.record_progress(10)
    assert_equal(control.progress().completed_bytes, 10)
    control.cancel()
    assert_true(control.is_cancelled())
    var observer = NoProgress()
    observer.on_progress(control.progress())
    print("Owned transfer control counters and cancellation passed")
