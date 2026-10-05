"""Internal fault harness: cancel only after the server commits completion."""
from std.atomic import Atomic
from std.collections import List
from std.ffi import external_call
from std.memory import Pointer
from std.os import getenv, abort
from std.testing import assert_equal, assert_true
from mojo_s3 import S3Store, S3Config, PutOptions
from mojo_s3.concurrent import controlled_multipart_upload_file
from mojo_s3.transfer_control import TransferControl, TransferState, NoProgress

comptime Raw = Pointer[UInt8, MutUntrackedOrigin]


@fieldwise_init
struct Monitor(Movable):
    var state: Pointer[TransferState, MutUntrackedOrigin]
    var stop: Pointer[Atomic[Int32], MutUntrackedOrigin]
    var signal: String


def watch(raw: Raw) abi("C") -> Optional[Raw]:
    var monitor = raw.unsafe_bitcast[Monitor]()
    while monitor[].stop[].load() == 0:
        if (
            external_call["access", Int32](
                monitor[].signal.as_c_string_span(), Int32(0)
            )
            == 0
        ):
            monitor[].state[].cancelled.store(1)
            break
        _ = external_call["usleep", Int32](UInt32(1000))
    return None


def main() raises:
    var store = S3Store(S3Config.from_env())
    var control = TransferControl()
    var observer = NoProgress()
    var stop = List[Atomic[Int32]]()
    stop.append(Atomic[Int32](0))
    var monitors = List[Monitor]()
    monitors.append(
        Monitor(
            control._state.unsafe_ptr().unsafe_origin_cast[
                MutUntrackedOrigin
            ](),
            stop.unsafe_ptr().unsafe_origin_cast[MutUntrackedOrigin](),
            getenv("S3_COMMIT_SIGNAL"),
        )
    )
    var thread = UInt(0)
    assert_equal(
        external_call["pthread_create", Int32](
            Pointer(to=thread),
            Optional[Raw](None),
            watch,
            monitors.unsafe_ptr().unsafe_bitcast[UInt8](),
        ),
        0,
    )
    var failed = False
    var etag = ""
    try:
        etag = controlled_multipart_upload_file(
            store,
            "bucket",
            "late",
            getenv("S3_STREAM_SOURCE"),
            2,
            5 * 1024 * 1024,
            PutOptions(),
            control,
            observer,
        ).etag
    except:
        failed = True
    stop[0].store(1)
    if external_call["pthread_join", Int32](thread, Optional[Raw](None)) != 0:
        abort()
    _ = monitors
    _ = stop
    assert_true(not failed)
    assert_true(control.is_cancelled())
    assert_equal(etag, "committed")
    print(
        "Cancellation after server commit returns success; monitor and all workers joined"
    )
