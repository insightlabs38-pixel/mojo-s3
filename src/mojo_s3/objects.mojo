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

    def __init__(out self, start: Int, end: Int = -1) raises:
        if start < 0 or end < -1 or (end >= 0 and end < start):
            raise Error("Invalid object range")
        self.start = start
        self.end = end

    def header(self) -> String:
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
