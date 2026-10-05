"""Small provider-neutral object-storage value types and synchronous contract."""
from std.collections import List
from mojo_s3.protocol import Field


struct ObjectMetadata(Copyable, Movable):
    var size: Int
    var etag: String
    var content_type: String
    var version_id: String
    var metadata: List[Field]
    var checksum: String
    var checksum_algorithm: String
    var checksum_verified: Bool

    def __init__(
        out self,
        size: Int,
        etag: String,
        content_type: String,
        version_id: String,
        var metadata: List[Field],
        checksum: String = "",
        checksum_algorithm: String = "",
        checksum_verified: Bool = False,
    ):
        self.size = size
        self.etag = etag
        self.content_type = content_type
        self.version_id = version_id
        self.metadata = metadata^
        self.checksum = checksum
        self.checksum_algorithm = checksum_algorithm
        self.checksum_verified = checksum_verified


@fieldwise_init
struct GetResult(Copyable, Movable):
    var data: List[UInt8]
    var metadata: ObjectMetadata


@fieldwise_init
struct PutResult(Copyable, Movable):
    var etag: String
    var version_id: String


@fieldwise_init
struct ObjectInfo(Copyable, Movable):
    var key: String
    var size: Int
    var etag: String
    var last_modified: String


@fieldwise_init
struct ListResult(Copyable, Movable):
    var objects: List[ObjectInfo]
    var prefixes: List[String]
    var truncated: Bool
    var next_token: String


struct PutOptions(Copyable, Movable):
    var content_type: String
    var metadata: List[Field]

    def __init__(out self, content_type: String = "application/octet-stream"):
        self.content_type = content_type
        self.metadata = List[Field]()


struct ListOptions(Copyable, Movable):
    var prefix: String
    var delimiter: String
    var max_keys: Int
    var continuation_token: String

    def __init__(
        out self,
        prefix: String = "",
        delimiter: String = "",
        max_keys: Int = 1000,
        continuation_token: String = "",
    ):
        self.prefix = prefix
        self.delimiter = delimiter
        self.max_keys = max_keys
        self.continuation_token = continuation_token


struct ObjectRange(Copyable, Movable):
    var start: Int
    var end: Int
    var suffix_length: Int

    def __init__(out self, start: Int, end: Int = -1) raises:
        if start < 0 or end < -1 or (end >= 0 and end < start):
            raise Error("Invalid object range")
        self.start = start
        self.end = end
        self.suffix_length = 0

    @staticmethod
    def suffix(length: Int) raises -> ObjectRange:
        """Request the last length bytes; lengths larger than the object clamp."""
        if length <= 0:
            raise Error("Suffix range length must be positive")
        var result = ObjectRange(0)
        result.suffix_length = length
        return result^

    def validate(self) raises:
        if (
            self.start < 0
            or self.end < -1
            or (self.end >= 0 and self.end < self.start)
            or self.suffix_length < 0
            or (self.suffix_length > 0 and (self.start != 0 or self.end != -1))
        ):
            raise Error("Invalid object range")

    def header(self) -> String:
        if self.suffix_length > 0:
            return "bytes=-" + String(self.suffix_length)
        return (
            "bytes="
            + String(self.start)
            + "-"
            + (String(self.end) if self.end >= 0 else "")
        )


trait ObjectStore(Movable):
    def put(
        mut self,
        bucket: String,
        key: String,
        data: List[UInt8],
        options: PutOptions = PutOptions(),
    ) raises -> PutResult:
        ...

    def get(mut self, bucket: String, key: String) raises -> GetResult:
        ...

    def head(mut self, bucket: String, key: String) raises -> ObjectMetadata:
        ...

    def exists(mut self, bucket: String, key: String) raises -> Bool:
        ...

    def delete(mut self, bucket: String, key: String) raises:
        ...

    def list(
        mut self, bucket: String, options: ListOptions = ListOptions()
    ) raises -> ListResult:
        ...

    def get_range(
        mut self, bucket: String, key: String, requested: ObjectRange
    ) raises -> GetResult:
        ...


struct ListPaginator(Movable):
    """Fetch one bounded page at a time, retaining only continuation state.

    Each returned ListResult preserves objects, common prefixes, truncation,
    and the server token. Stop when done becomes True. Errors leave state
    unchanged so callers can retry. A server token that fails to advance is
    rejected; max_pages bounds longer token cycles as well.
    """

    var bucket: String
    var options: ListOptions
    var done: Bool
    var pages_loaded: Int
    var max_pages: Int

    def __init__(
        out self,
        bucket: String,
        var options: ListOptions = ListOptions(),
        max_pages: Int = 1000000,
    ) raises:
        if options.max_keys < 1 or options.max_keys > 1000:
            raise Error("max_keys must be 1..1000")
        if max_pages < 1:
            raise Error("max_pages must be positive")
        self.bucket = bucket
        self.options = options^
        self.done = False
        self.pages_loaded = 0
        self.max_pages = max_pages

    def next_page[
        Store: ObjectStore
    ](mut self, mut store: Store) raises -> ListResult:
        if self.done:
            raise Error("Listing pagination is complete")
        if self.pages_loaded >= self.max_pages:
            raise Error("Listing pagination exceeded max_pages")
        var page = store.list(self.bucket, self.options)
        if page.truncated and (
            not page.next_token
            or page.next_token == self.options.continuation_token
        ):
            raise Error("Truncated listing continuation token did not advance")
        self.options.continuation_token = (
            page.next_token if page.truncated else ""
        )
        self.done = not page.truncated
        self.pages_loaded += 1
        return page^
