"""File transfer policy over the existing streaming and multipart primitives."""
from mojo_s3.client import S3Store
from mojo_s3.objects import (
    PutOptions,
    PutResult,
    ObjectMetadata,
    CopyOptions,
    CopyResult,
    ReadOptions,
)
from mojo_s3.multipart_copy import multipart_copy_object
from mojo_s3.download_plan import plan_download
from mojo_s3.files import NativeFile
from mojo_s3.multipart_plan import MAX_PART_BYTES, FILE_BUFFER_BYTES
from mojo_s3.multipart import multipart_upload_file
from mojo_s3.concurrent import (
    concurrent_multipart_upload_file,
    controlled_multipart_upload_file,
)
from mojo_s3.downloads import concurrent_download_file
from mojo_s3.transfer_control import (
    TransferControl,
    ProgressObserver,
    NoProgress,
)


struct TransferOptions(Copyable, Movable):
    var multipart_threshold: Int
    var part_size: Int
    var workers: Int
    var max_in_flight_bytes: Int

    def __init__(
        out self,
        multipart_threshold: Int = 64 * 1024 * 1024,
        part_size: Int = 8 * 1024 * 1024,
        workers: Int = 4,
        max_in_flight_bytes: Int = 64 * 1024 * 1024,
    ):
        self.multipart_threshold = multipart_threshold
        self.part_size = part_size
        self.workers = workers
        self.max_in_flight_bytes = max_in_flight_bytes

    def validate(self) raises:
        if self.multipart_threshold < 0:
            raise Error("Multipart threshold must be nonnegative")
        if self.workers < 1 or self.workers > 16:
            raise Error("Transfer workers must be 1..16")
        if (
            self.part_size < 5 * 1024 * 1024
            or Int64(self.part_size) > MAX_PART_BYTES
        ):
            raise Error("Transfer part size must be 5 MiB..5 GiB")
        if self.max_in_flight_bytes < self.workers * FILE_BUFFER_BYTES:
            raise Error("Configured streaming buffers exceed transfer budget")

    def download_range_size(self) raises -> Int:
        self.validate()
        return min(
            min(self.part_size, 64 * 1024 * 1024),
            self.max_in_flight_bytes // self.workers,
        )

    def uses_multipart(self, size: Int) raises -> Bool:
        self.validate()
        if size < 0:
            raise Error("Transfer size must be nonnegative")
        return size > 0 and (
            size >= self.multipart_threshold or Int64(size) > MAX_PART_BYTES
        )


struct TransferManager(Movable):
    """Own a store and select streamed PUT or bounded multipart for files.

    The part-buffer budget excludes request copies, response buffers, native
    libraries and allocator overhead. Large downloads use bounded ranges with
    atomic destination replacement. A manager has one active owner, like its store.
    """

    var store: S3Store
    var options: TransferOptions

    def __init__(
        out self,
        var store: S3Store,
        options: TransferOptions = TransferOptions(),
    ) raises:
        options.validate()
        self.store = store^
        self.options = options.copy()

    def upload_file(
        mut self,
        bucket: String,
        key: String,
        source: String,
        options: PutOptions = PutOptions(),
    ) raises -> PutResult:
        var file = NativeFile(source)
        if not self.options.uses_multipart(file.length()):
            return self.store.upload_file(bucket, key, source, options)
        if self.options.workers == 1:
            return multipart_upload_file(
                self.store, bucket, key, source, self.options.part_size, options
            )
        return concurrent_multipart_upload_file(
            self.store,
            bucket,
            key,
            source,
            self.options.workers,
            self.options.part_size,
            options,
        )

    def copy_object(
        mut self,
        source_bucket: String,
        source_key: String,
        bucket: String,
        key: String,
        options: CopyOptions = CopyOptions(),
    ) raises -> CopyResult:
        var metadata = self.store.head(
            source_bucket,
            source_key,
            ReadOptions(options.source_version_id, options.source_conditions),
        )
        if Int64(metadata.size) <= MAX_PART_BYTES:
            return self.store.copy_object(
                source_bucket, source_key, bucket, key, options
            )
        return multipart_copy_object(
            self.store,
            source_bucket,
            source_key,
            bucket,
            key,
            options,
            Int64(self.options.part_size),
        )

    def download_file(
        mut self, bucket: String, key: String, destination: String
    ) raises -> ObjectMetadata:
        self.options.validate()
        var metadata = self.store.head(bucket, key)
        if metadata.size < self.options.multipart_threshold:
            return self.store.download_file(bucket, key, destination)
        var plan = plan_download(
            Int64(metadata.size),
            Int64(self.options.part_size),
            self.options.workers,
            Int64(self.options.max_in_flight_bytes),
        )
        var control = TransferControl()
        var observer = NoProgress()
        return concurrent_download_file(
            self.store,
            bucket,
            key,
            destination,
            max(1, plan.workers),
            Int(plan.range_size_bytes),
            control,
            observer,
        )

    def download_file[
        Observer: ProgressObserver
    ](
        mut self,
        bucket: String,
        key: String,
        destination: String,
        mut control: TransferControl,
        mut observer: Observer,
    ) raises -> ObjectMetadata:
        self.options.validate()
        var metadata = self.store.head(bucket, key)
        var plan = plan_download(
            Int64(metadata.size),
            Int64(self.options.part_size),
            self.options.workers,
            Int64(self.options.max_in_flight_bytes),
        )
        return concurrent_download_file(
            self.store,
            bucket,
            key,
            destination,
            max(1, plan.workers),
            Int(plan.range_size_bytes),
            control,
            observer,
        )

    def upload_file[
        Observer: ProgressObserver
    ](
        mut self,
        bucket: String,
        key: String,
        source: String,
        options: PutOptions,
        mut control: TransferControl,
        mut observer: Observer,
    ) raises -> PutResult:
        self.options.validate()
        # Controlled uploads use multipart for nonempty files, including small
        # files, so cancellation can abort an uncommitted upload ID.
        return controlled_multipart_upload_file(
            self.store,
            bucket,
            key,
            source,
            self.options.workers,
            self.options.part_size,
            options,
            control,
            observer,
        )
