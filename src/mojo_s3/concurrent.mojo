"""Linux bounded multipart workers. Each thread owns its store, file and buffers.

No exception crosses the C ABI. Results occupy disjoint preallocated slots;
parents inspect them only after joining every launched worker.
"""
from std.atomic import Atomic
from std.collections import List
from std.ffi import external_call
from std.memory import Pointer
from std.os import abort as process_abort
from mojo_s3.client import S3Store
from mojo_s3.config import S3Config
from mojo_s3.errors import S3Error
from mojo_s3.http import CurlTransport
from mojo_s3.files import NativeFile, errno_value
from mojo_s3.multipart import (
    initiate,
    upload_part,
    complete,
    abort,
    CompletedPart,
)
from mojo_s3.objects import PutOptions, PutResult

comptime Raw = Pointer[UInt8, MutUntrackedOrigin]
comptime StopFlag = Atomic[Int32]


@fieldwise_init
struct PartOutcome(Copyable, Movable):
    var number: Int
    var etag: String
    var failed: Bool
    var error: Optional[S3Error]


@fieldwise_init
struct MultipartWorker(Movable):
    var config: S3Config
    var bucket: String
    var key: String
    var source: String
    var upload_id: String
    var size: Int
    var part_size: Int
    var first_part: Int
    var stride: Int
    var count: Int
    var outcomes: Pointer[PartOutcome, MutUntrackedOrigin]
    var stop: Pointer[StopFlag, MutUntrackedOrigin]
    var timeout_ms: Int
    var connect_timeout_ms: Int
    var max_response_bytes: Int
    var verify_tls: Bool
    var ca_bundle: String


def multipart_worker(raw: Raw) abi("C") -> Optional[Raw]:
    var worker = raw.unsafe_bitcast[MultipartWorker]()
    var number = worker[].first_part
    try:
        var transport = CurlTransport(
            worker[].timeout_ms,
            worker[].connect_timeout_ms,
            worker[].max_response_bytes,
            worker[].verify_tls,
            worker[].ca_bundle,
        )
        var store = S3Store(worker[].config, transport^)
        var file = NativeFile(worker[].source)
        while number <= worker[].count and worker[].stop[].load() == 0:
            try:
                var offset_in_file = (number - 1) * worker[].part_size
                if (
                    external_call["lseek", Int64](
                        file.fd, Int64(offset_in_file), Int32(0)
                    )
                    < 0
                ):
                    raise Error("Cannot seek multipart source")
                var length = min(
                    worker[].part_size, worker[].size - offset_in_file
                )
                var buffer = List[UInt8](length=length, fill=0)
                var offset = 0
                while offset < length:
                    var n = external_call["read", Int64](
                        Int(file.fd),
                        buffer.unsafe_ptr().unsafe_offset(offset),
                        length - offset,
                    )
                    if n < 0 and errno_value() == 4:
                        continue
                    if n <= 0:
                        raise Error("Cannot read stable multipart source")
                    offset += Int(n)
                var part = upload_part(
                    store,
                    worker[].bucket,
                    worker[].key,
                    worker[].upload_id,
                    number,
                    buffer,
                )
                worker[].outcomes[unsafe_offset=number - 1] = PartOutcome(
                    number, part.etag, False, None
                )
            except:
                worker[].outcomes[unsafe_offset=number - 1] = PartOutcome(
                    number, "", True, store.last_error.copy()
                )
                worker[].stop[].store(1)
                break
            number += worker[].stride
        _ = file
    except:
        worker[].outcomes[unsafe_offset=worker[].first_part - 1] = PartOutcome(
            worker[].first_part, "", True, None
        )
        worker[].stop[].store(1)
    return None


def run_workers(
    mut workers: List[MultipartWorker], fail_after: Int = -1
) raises:
    """Internal join scope. fail_after is a deterministic launch-failure test hook."""
    if not len(workers) or len(workers) > 16:
        raise Error("Worker count must be 1..16")
    var threads = List[UInt](length=len(workers), fill=0)
    var launched = 0
    var launch_error = False
    for i in range(len(workers)):
        if i == fail_after:
            launch_error = True
            break
        var code = external_call["pthread_create", Int32](
            Pointer(to=threads[i]),
            Optional[Raw](None),
            multipart_worker,
            Pointer(to=workers[i]).unsafe_bitcast[UInt8](),
        )
        if code != 0:
            launch_error = True
            break
        launched += 1
    if launch_error:
        workers[0].stop[].store(1)
    for i in range(launched):
        # These are valid, joinable threads owned only by this scope. A failure
        # would violate that invariant; abort rather than free live contexts.
        if (
            external_call["pthread_join", Int32](
                threads[i], Optional[Raw](None)
            )
            != 0
        ):
            process_abort()
    _ = workers
    if launch_error:
        raise Error(
            "Cannot launch all multipart workers; launched workers joined"
        )


def concurrent_multipart_upload_file(
    mut store: S3Store,
    bucket: String,
    key: String,
    source: String,
    concurrency: Int = 4,
    part_size: Int = 8 * 1024 * 1024,
    options: PutOptions = PutOptions(),
    *,
    _fail_after: Int = -1,
) raises -> PutResult:
    if (
        concurrency < 1
        or concurrency > 16
        or part_size < 5 * 1024 * 1024
        or part_size > 64 * 1024 * 1024
    ):
        raise Error("Concurrency must be 1..16 and part_size 5..64 MiB")
    var source_file = NativeFile(source)
    var size = source_file.length()
    if size == 0:
        return store.put(bucket, key, List[UInt8](), options)
    var count = (size - 1) // part_size + 1
    if count > 10000:
        raise Error("Multipart upload exceeds 10000 parts")
    var worker_count = min(concurrency, count)
    var upload_id = initiate(store, bucket, key, options)
    try:
        var outcomes = List[PartOutcome](
            length=count, fill=PartOutcome(0, "", False, None)
        )
        var stopped = StopFlag(0)
        var workers = List[MultipartWorker](capacity=worker_count)
        for i in range(worker_count):
            workers.append(
                MultipartWorker(
                    store.config.copy(),
                    bucket,
                    key,
                    source,
                    upload_id,
                    size,
                    part_size,
                    i + 1,
                    worker_count,
                    count,
                    outcomes.unsafe_ptr().unsafe_origin_cast[
                        MutUntrackedOrigin
                    ](),
                    Pointer(to=stopped).unsafe_origin_cast[
                        MutUntrackedOrigin
                    ](),
                    store.transport.timeout_ms,
                    store.transport.connect_timeout_ms,
                    store.transport.max_response_bytes,
                    store.transport.verify_tls,
                    store.transport.ca_bundle,
                )
            )
        run_workers(workers, _fail_after)
        var parts = List[CompletedPart]()
        for outcome in outcomes:
            if outcome.failed:
                store.last_error = outcome.error.copy()
                raise Error(
                    "Concurrent multipart worker failed at part "
                    + String(outcome.number)
                )
        for outcome in outcomes:
            if not outcome.number or not outcome.etag:
                raise Error(
                    "Concurrent multipart cancelled before all parts completed"
                )
            parts.append(CompletedPart(outcome.number, outcome.etag))
        _ = stopped
        _ = source_file
        return complete(store, bucket, key, upload_id, parts)
    except e:
        var original_error = store.last_error.copy()
        try:
            abort(store, bucket, key, upload_id)
        except:
            store.last_error = original_error^
            raise Error(
                "Concurrent multipart transfer and cleanup failed; orphan upload ID: "
                + upload_id
            )
        store.last_error = original_error^
        raise e^
