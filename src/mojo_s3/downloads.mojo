"""Linux bounded ranged downloads into one uncommitted random-access file."""
from std.atomic import Atomic
from std.collections import List
from std.ffi import external_call
from std.memory import Pointer
from mojo_s3.client import S3Store, metadata_of
from mojo_s3.checksums import full_checksum
from mojo_s3.config import S3Config
from mojo_s3.http import CurlTransport
from mojo_s3.objects import ObjectMetadata, ObjectRange, ReadOptions, Conditions
from mojo_s3.files import NativeFile, errno_value, digest_file
from mojo_s3.crypto import base64_encode
from mojo_s3.protocol import Field
from mojo_s3.errors import S3Error
from mojo_s3.transfer_control import (
    TransferControl,
    TransferState,
    ProgressObserver,
    join_observed,
)

comptime DownloadRaw = Pointer[UInt8, MutUntrackedOrigin]
comptime ControlPtr = Pointer[TransferState, MutUntrackedOrigin]


@fieldwise_init
struct DownloadOutcome(Copyable, Movable):
    var length: Int
    var completed_ranges: Int
    var error: Optional[S3Error]
    var failed: Bool


@fieldwise_init
struct DownloadWorker(Movable):
    var config: S3Config
    var bucket: String
    var key: String
    var etag: String
    var version: String
    var fd: Int32
    var size: Int
    var range_size: Int
    var first: Int
    var stride: Int
    var count: Int
    var outcomes: Pointer[DownloadOutcome, MutUntrackedOrigin]
    var control: ControlPtr
    var stopped: Pointer[Atomic[Int32], MutUntrackedOrigin]
    var timeout_ms: Int
    var connect_timeout_ms: Int
    var max_response_bytes: Int
    var verify_tls: Bool
    var ca_bundle: String


def download_worker(raw: DownloadRaw) abi("C") -> Optional[DownloadRaw]:
    var worker = raw.unsafe_bitcast[DownloadWorker]()
    var number = worker[].first
    try:
        var transport = CurlTransport(
            worker[].timeout_ms,
            worker[].connect_timeout_ms,
            min(worker[].max_response_bytes, worker[].range_size),
            worker[].verify_tls,
            worker[].ca_bundle,
        )
        var store = S3Store(worker[].config, transport^)
        while (
            number < worker[].count
            and worker[].stopped[].load() == 0
            and worker[].control[].cancelled.load() == 0
        ):
            try:
                var start = number * worker[].range_size
                var length = min(worker[].range_size, worker[].size - start)
                var result = store.get_range(
                    worker[].bucket,
                    worker[].key,
                    ObjectRange(start, start + length - 1),
                    ReadOptions(
                        worker[].version, Conditions(if_match=worker[].etag)
                    ),
                )
                if (
                    result.metadata.size != worker[].size
                    or result.metadata.etag != worker[].etag
                    or len(result.data) != length
                    or (
                        worker[].version
                        and result.metadata.version_id != worker[].version
                    )
                ):
                    raise Error("Concurrent download object identity changed")
                var written = 0
                while written < length:
                    var n = external_call["pwrite", Int64](
                        worker[].fd,
                        result.data.unsafe_ptr().unsafe_offset(written),
                        length - written,
                        Int64(start + written),
                    )
                    if n < 0 and errno_value() == 4:
                        continue
                    if n <= 0:
                        raise Error("Cannot write downloaded range")
                    written += Int(n)
                worker[].outcomes[unsafe_offset=worker[].first].length += length
                worker[].outcomes[
                    unsafe_offset=worker[].first
                ].completed_ranges += 1
                _ = worker[].control[].completed_bytes.fetch_add(Int64(length))
                _ = worker[].control[].completed_parts.fetch_add(1)
            except:
                worker[].outcomes[
                    unsafe_offset=worker[].first
                ].error = store.last_error.copy()
                worker[].outcomes[unsafe_offset=worker[].first].failed = True
                worker[].stopped[].store(1)
                break
            number += worker[].stride
    except:
        worker[].outcomes[unsafe_offset=worker[].first].failed = True
        worker[].stopped[].store(1)
    return None


def concurrent_download_file[
    Observer: ProgressObserver
](
    mut store: S3Store,
    bucket: String,
    key: String,
    destination: String,
    workers_count: Int,
    range_size: Int,
    mut control: TransferControl,
    mut observer: Observer,
    fail_after: Int = -1,
    _write_fd_override: Int32 = -1,
) raises -> ObjectMetadata:
    if (
        workers_count < 1
        or workers_count > 16
        or range_size < 1
        or range_size > 64 * 1024 * 1024
    ):
        raise Error(
            "Download workers must be 1..16 and range size 1 byte..64 MiB"
        )
    store.last_error = None
    var head_headers: List[Field] = [Field("x-amz-checksum-mode", "ENABLED")]
    var head = store.request(
        "HEAD", bucket, key, List[Field](), head_headers, List[UInt8]()
    )
    var metadata = metadata_of(head)
    if not metadata.etag:
        raise Error("Concurrent download requires a stable object ETag")
    control.start(metadata.size)
    var file = NativeFile(destination, True)
    if external_call["ftruncate", Int32](file.fd, Int64(metadata.size)) != 0:
        raise Error("Cannot size temporary download")
    if control.is_cancelled():
        store.last_error = S3Error(
            0, "Cancelled", "Transfer cancelled", "", "", key, "Cancelled"
        )
        raise Error("Download cancelled before launch")
    if metadata.size == 0:
        var result = store.get(
            bucket,
            key,
            ReadOptions(
                metadata.version_id, Conditions(if_match=metadata.etag)
            ),
        )
        if len(result.data) != 0:
            raise Error("Empty object changed before download")
        try:
            observer.on_progress(control.progress())
            if observer.cancel_requested():
                control.cancel()
        except e:
            control.mark_observer_failed()
            store.last_error = S3Error(
                0,
                "ProgressCallbackFailure",
                "Progress observer failed",
                "",
                "",
                key,
                "LocalTransfer",
            )
            raise e^
        if control.is_cancelled():
            store.last_error = S3Error(
                0, "Cancelled", "Transfer cancelled", "", "", key, "Cancelled"
            )
            raise Error("Empty download cancelled")
        file.commit(destination)
        return result.metadata.copy()
    var count = (metadata.size - 1) // range_size + 1
    if count > 1000000:
        raise Error("Download exceeds bounded range count")
    var worker_count = min(workers_count, count)
    var outcomes = List[DownloadOutcome](
        length=worker_count, fill=DownloadOutcome(0, 0, None, False)
    )
    var stopped = List[Atomic[Int32]](capacity=1)
    stopped.append(Atomic[Int32](0))
    var workers = List[DownloadWorker](capacity=worker_count)
    for i in range(worker_count):
        workers.append(
            DownloadWorker(
                store.config.copy(),
                bucket,
                key,
                metadata.etag,
                metadata.version_id,
                _write_fd_override if _write_fd_override >= 0 else file.fd,
                metadata.size,
                range_size,
                i,
                worker_count,
                count,
                outcomes.unsafe_ptr().unsafe_origin_cast[MutUntrackedOrigin](),
                control._state.unsafe_ptr().unsafe_origin_cast[
                    MutUntrackedOrigin
                ](),
                Pointer(to=stopped[0]).unsafe_origin_cast[MutUntrackedOrigin](),
                store.transport.timeout_ms,
                store.transport.connect_timeout_ms,
                store.transport.max_response_bytes,
                store.transport.verify_tls,
                store.transport.ca_bundle,
            )
        )
    var threads = List[UInt](length=worker_count, fill=0)
    var launched = 0
    var launch_failed = False
    for i in range(worker_count):
        if i == fail_after:
            launch_failed = True
            break
        if (
            external_call["pthread_create", Int32](
                Pointer(to=threads[i]),
                Optional[DownloadRaw](None),
                download_worker,
                Pointer(to=workers[i]).unsafe_bitcast[UInt8](),
            )
            != 0
        ):
            launch_failed = True
            break
        launched += 1
    if launch_failed:
        stopped[0].store(1)
    try:
        join_observed(threads, launched, control, observer)
    except e:
        store.last_error = S3Error(
            0,
            "ProgressCallbackFailure",
            "Progress observer failed",
            "",
            "",
            key,
            "LocalTransfer",
        )
        raise e^
    _ = workers
    _ = stopped
    if launch_failed:
        store.last_error = S3Error(
            0,
            "ThreadLaunchFailure",
            "Cannot launch all download workers",
            "",
            "",
            key,
            "LocalTransfer",
        )
        raise Error("Download partial launch failed; all workers joined")
    if control.is_cancelled():
        store.last_error = S3Error(
            0, "Cancelled", "Transfer cancelled", "", "", key, "Cancelled"
        )
        raise Error("Download cancelled; all workers joined")
    var completed_bytes = 0
    var completed_ranges = 0
    for outcome in outcomes:
        if outcome.failed:
            store.last_error = outcome.error.copy()
            if not store.last_error:
                store.last_error = S3Error(
                    0,
                    "RangeTransferFailure",
                    "Cannot verify or write downloaded range",
                    "",
                    "",
                    key,
                    "LocalTransfer",
                )
            raise Error("Concurrent download range failed; all workers joined")
        completed_bytes += outcome.length
        completed_ranges += outcome.completed_ranges
    if (
        completed_bytes != metadata.size
        or completed_ranges != count
        or control.progress().completed_parts != count
    ):
        raise Error("Concurrent download did not finish exactly every range")
    if (
        file.length() != metadata.size
        or control.progress().completed_bytes != metadata.size
    ):
        raise Error(
            "Concurrent download final size mismatch: file="
            + String(file.length())
            + " completed="
            + String(control.progress().completed_bytes)
            + " expected="
            + String(metadata.size)
        )
    if full_checksum(head.headers).value:
        metadata.checksum_verified = store.check_checksum(
            head, base64_encode(digest_file(file, metadata.checksum_algorithm))
        )
        metadata.checksum_state = "verified"
    if control.is_cancelled():
        store.last_error = S3Error(
            0,
            "Cancelled",
            "Transfer cancelled before replacement",
            "",
            "",
            key,
            "Cancelled",
        )
        raise Error("Download cancelled before replacement; all workers joined")
    file.commit(destination)
    return metadata^
