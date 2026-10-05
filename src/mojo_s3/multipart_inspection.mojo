"""Bounded multipart inspection. Listing never aborts discovered uploads."""
from std.collections import List
from mojo_s3.client import S3Store, decimal
from mojo_s3.protocol import Field
from mojo_s3.xml import parse_xml, child_text
from mojo_s3.multipart_plan import MAX_PART_BYTES


@fieldwise_init
struct UploadedPart(Copyable, Movable):
    var number: Int
    var etag: String
    var size_bytes: Int64
    var last_modified: String


@fieldwise_init
struct PartsPage(Copyable, Movable):
    var parts: List[UploadedPart]
    var truncated: Bool
    var next_part_number_marker: Int


@fieldwise_init
struct MultipartUpload(Copyable, Movable):
    var key: String
    var upload_id: String
    var initiated: String
    var storage_class: String


@fieldwise_init
struct MultipartUploadsPage(Copyable, Movable):
    var uploads: List[MultipartUpload]
    var truncated: Bool
    var next_key_marker: String
    var next_upload_id_marker: String


def truncated_value(value: String) raises -> Bool:
    if value != "true" and value != "false":
        raise Error("Missing or invalid multipart truncation flag")
    return value == "true"


def list_parts(
    mut store: S3Store,
    bucket: String,
    key: String,
    upload_id: String,
    part_number_marker: Int = 0,
    max_parts: Int = 1000,
) raises -> PartsPage:
    if (
        not upload_id
        or part_number_marker < 0
        or part_number_marker > 10000
        or max_parts < 1
        or max_parts > 1000
    ):
        raise Error("Invalid ListParts bounds")
    var query: List[Field] = [
        Field("uploadId", upload_id),
        Field("part-number-marker", String(part_number_marker)),
        Field("max-parts", String(max_parts)),
    ]
    var response = store.request(
        "GET", bucket, key, query, List[Field](), List[UInt8]()
    )
    var nodes = parse_xml(
        String(
            from_utf8=Span(
                unsafe_ptr=response.body.unsafe_ptr(), length=len(response.body)
            )
        )
    )
    if (
        nodes[0].name != "ListPartsResult"
        or child_text(nodes, 0, "UploadId") != upload_id
    ):
        raise Error("Unexpected ListParts identity or result")
    var parts = List[UploadedPart]()
    var previous = part_number_marker
    for i in range(len(nodes)):
        if nodes[i].parent == 0 and nodes[i].name == "Part":
            var number = decimal(child_text(nodes, i, "PartNumber"))
            var etag = child_text(nodes, i, "ETag")
            var size = Int64(decimal(child_text(nodes, i, "Size")))
            if (
                number <= previous
                or number > 10000
                or not etag
                or len(parts) >= max_parts
                or size > MAX_PART_BYTES
            ):
                raise Error("Invalid ListParts ordering/count/ETag")
            previous = number
            parts.append(
                UploadedPart(
                    number,
                    etag,
                    size,
                    child_text(nodes, i, "LastModified"),
                )
            )
    var truncated = truncated_value(child_text(nodes, 0, "IsTruncated"))
    var marker = 0
    if truncated:
        marker = decimal(child_text(nodes, 0, "NextPartNumberMarker"))
        if marker <= part_number_marker or marker > 10000 or marker < previous:
            raise Error("ListParts marker failed to advance")
    return PartsPage(parts^, truncated, marker)


def list_multipart_uploads(
    mut store: S3Store,
    bucket: String,
    prefix: String = "",
    key_marker: String = "",
    upload_id_marker: String = "",
    max_uploads: Int = 1000,
) raises -> MultipartUploadsPage:
    if (
        max_uploads < 1
        or max_uploads > 1000
        or (upload_id_marker and not key_marker)
    ):
        raise Error("Invalid multipart upload listing bounds")
    var query: List[Field] = [
        Field("uploads", ""),
        Field("max-uploads", String(max_uploads)),
    ]
    for field in [
        Field("prefix", prefix),
        Field("key-marker", key_marker),
        Field("upload-id-marker", upload_id_marker),
    ]:
        if field.value:
            query.append(field.copy())
    var response = store.request(
        "GET", bucket, "", query, List[Field](), List[UInt8]()
    )
    var nodes = parse_xml(
        String(
            from_utf8=Span(
                unsafe_ptr=response.body.unsafe_ptr(), length=len(response.body)
            )
        )
    )
    if nodes[0].name != "ListMultipartUploadsResult":
        raise Error("Unexpected multipart uploads listing result")
    var uploads = List[MultipartUpload]()
    var previous_key = key_marker
    for i in range(len(nodes)):
        if nodes[i].parent == 0 and nodes[i].name == "Upload":
            var key = child_text(nodes, i, "Key")
            var upload_id = child_text(nodes, i, "UploadId")
            if (
                not key
                or not upload_id
                or not key.startswith(prefix)
                or len(uploads) >= max_uploads
                or key < previous_key
                or (key == key_marker and upload_id == upload_id_marker)
            ):
                raise Error("Invalid multipart upload listing entry")
            for existing in uploads:
                if existing.key == key and existing.upload_id == upload_id:
                    raise Error("Duplicate multipart upload listing entry")
            uploads.append(
                MultipartUpload(
                    key,
                    upload_id,
                    child_text(nodes, i, "Initiated"),
                    child_text(nodes, i, "StorageClass"),
                )
            )
            previous_key = key
    var truncated = truncated_value(child_text(nodes, 0, "IsTruncated"))
    var next_key = child_text(nodes, 0, "NextKeyMarker")
    var next_id = child_text(nodes, 0, "NextUploadIdMarker")
    if truncated and (
        not next_key
        or not next_key.startswith(prefix)
        or next_key < previous_key
        or (next_key == key_marker and next_id == upload_id_marker)
    ):
        raise Error("Multipart upload markers failed to advance")
    return MultipartUploadsPage(uploads^, truncated, next_key, next_id)


struct PartsPaginator(Movable):
    var bucket: String
    var key: String
    var upload_id: String
    var marker: Int
    var page_size: Int
    var pages_loaded: Int
    var max_pages: Int
    var done: Bool

    def __init__(
        out self,
        bucket: String,
        key: String,
        upload_id: String,
        page_size: Int = 1000,
        max_pages: Int = 10000,
    ) raises:
        if not upload_id or page_size < 1 or page_size > 1000 or max_pages < 1:
            raise Error("Invalid parts paginator")
        self.bucket = bucket
        self.key = key
        self.upload_id = upload_id
        self.marker = 0
        self.page_size = page_size
        self.pages_loaded = 0
        self.max_pages = max_pages
        self.done = False

    def next_page(mut self, mut store: S3Store) raises -> PartsPage:
        if self.done or self.pages_loaded >= self.max_pages:
            raise Error("Parts pagination complete or page bound exceeded")
        var page = list_parts(
            store,
            self.bucket,
            self.key,
            self.upload_id,
            self.marker,
            self.page_size,
        )
        self.marker = page.next_part_number_marker
        self.done = not page.truncated
        self.pages_loaded += 1
        return page^


struct MultipartUploadsPaginator(Movable):
    var bucket: String
    var prefix: String
    var key_marker: String
    var upload_id_marker: String
    var page_size: Int
    var pages_loaded: Int
    var max_pages: Int
    var done: Bool

    def __init__(
        out self,
        bucket: String,
        prefix: String = "",
        page_size: Int = 1000,
        max_pages: Int = 1000000,
    ) raises:
        if page_size < 1 or page_size > 1000 or max_pages < 1:
            raise Error("Invalid multipart uploads paginator")
        self.bucket = bucket
        self.prefix = prefix
        self.key_marker = ""
        self.upload_id_marker = ""
        self.page_size = page_size
        self.pages_loaded = 0
        self.max_pages = max_pages
        self.done = False

    def next_page(mut self, mut store: S3Store) raises -> MultipartUploadsPage:
        if self.done or self.pages_loaded >= self.max_pages:
            raise Error(
                "Multipart uploads pagination complete or page bound exceeded"
            )
        var page = list_multipart_uploads(
            store,
            self.bucket,
            self.prefix,
            self.key_marker,
            self.upload_id_marker,
            self.page_size,
        )
        self.key_marker = page.next_key_marker
        self.upload_id_marker = page.next_upload_id_marker
        self.done = not page.truncated
        self.pages_loaded += 1
        return page^
