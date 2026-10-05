"""File transfer policy over the existing streaming and multipart primitives."""
from mojo_s3.client import S3Store
from mojo_s3.objects import PutOptions, PutResult, ObjectMetadata
from mojo_s3.files import NativeFile
from mojo_s3.multipart import multipart_upload_file
from mojo_s3.concurrent import concurrent_multipart_upload_file


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
            or self.part_size > 64 * 1024 * 1024
        ):
            raise Error("Transfer part size must be 5..64 MiB")
        if self.max_in_flight_bytes < self.workers * self.part_size:
            raise Error("Configured multipart buffers exceed transfer budget")

    def uses_multipart(self, size: Int) raises -> Bool:
        self.validate()
        if size < 0:
            raise Error("Transfer size must be nonnegative")
        return size > 0 and size >= self.multipart_threshold


struct TransferManager(Movable):
    """Own a store and select streamed PUT or bounded multipart for files.

    The part-buffer budget excludes request copies, response buffers, native
    libraries and allocator overhead. Downloads retain the store's atomic
    streamed-file behavior. A manager has one active owner, like its store.
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

    def download_file(
        mut self, bucket: String, key: String, destination: String
    ) raises -> ObjectMetadata:
        return self.store.download_file(bucket, key, destination)
