"""Explicit S3 multipart capability and a sequential, bounded-memory file helper."""
from std.collections import List
from std.ffi import external_call
from mojo_s3.client import S3Store
from mojo_s3.protocol import Field, get_header
from mojo_s3.objects import PutOptions, PutResult
from mojo_s3.crypto import bytes_of
from mojo_s3.xml import parse_xml, child_text
from mojo_s3.errors import parse_s3_error
from mojo_s3.files import NativeFile, errno_value
from mojo_s3.options import put_headers


@fieldwise_init
struct CompletedPart(Copyable, Movable):
    var number: Int
    var etag: String


def escape_xml(value: String) -> String:
    return (
        value.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
        .replace("'", "&apos;")
    )


def completion_manifest(parts: List[CompletedPart]) raises -> String:
    if not len(parts) or len(parts) > 10000:
        raise Error("Multipart completion requires 1..10000 parts")
    var sorted = parts.copy()
    for i in range(1, len(sorted)):
        var j = i
        while j > 0 and sorted[j].number < sorted[j - 1].number:
            var tmp = sorted[j].copy()
            sorted[j] = sorted[j - 1].copy()
            sorted[j - 1] = tmp^
            j -= 1
    var xml = "<CompleteMultipartUpload>"
    var prior = 0
    for part in sorted:
        if part.number <= prior or part.number > 10000 or not part.etag:
            raise Error("Invalid/duplicate multipart part number or empty ETag")
        prior = part.number
        xml += (
            "<Part><PartNumber>"
            + String(part.number)
            + "</PartNumber><ETag>"
            + escape_xml(part.etag)
            + "</ETag></Part>"
        )
    return xml + "</CompleteMultipartUpload>"


def initiate(
    mut store: S3Store,
    bucket: String,
    key: String,
    options: PutOptions = PutOptions(),
) raises -> String:
    var query: List[Field] = [Field("uploads", "")]
    var headers = put_headers(options, False)
    var response = store.request(
        "POST", bucket, key, query, headers, List[UInt8](), False
    )
    var nodes = parse_xml(
        String(
            from_utf8=Span(
                unsafe_ptr=response.body.unsafe_ptr(), length=len(response.body)
            )
        )
    )
    if nodes[0].name != "InitiateMultipartUploadResult":
        raise Error("Unexpected multipart initiation response")
    var upload_id = child_text(nodes, 0, "UploadId")
    if not upload_id:
        raise Error("Multipart response has no UploadId")
    return upload_id


def upload_part(
    mut store: S3Store,
    bucket: String,
    key: String,
    upload_id: String,
    number: Int,
    data: List[UInt8],
) raises -> CompletedPart:
    if (
        not upload_id
        or number < 1
        or number > 10000
        or len(data) > 5 * 1024 * 1024 * 1024
    ):
        raise Error("Invalid multipart part")
    var query: List[Field] = [
        Field("uploadId", upload_id),
        Field("partNumber", String(number)),
    ]
    var response = store.request("PUT", bucket, key, query, List[Field](), data)
    var etag = get_header(response.headers, "etag")
    if not etag:
        raise Error("UploadPart response has no ETag")
    return CompletedPart(number, etag)


def complete(
    mut store: S3Store,
    bucket: String,
    key: String,
    upload_id: String,
    parts: List[CompletedPart],
) raises -> PutResult:
    if not upload_id:
        raise Error("UploadId required")
    var query: List[Field] = [Field("uploadId", upload_id)]
    var headers: List[Field] = [Field("content-type", "application/xml")]
    var response = store.request(
        "POST",
        bucket,
        key,
        query,
        headers,
        bytes_of(completion_manifest(parts)),
        False,
    )
    var nodes = parse_xml(
        String(
            from_utf8=Span(
                unsafe_ptr=response.body.unsafe_ptr(), length=len(response.body)
            )
        )
    )
    if nodes[0].name == "Error":
        var error = parse_s3_error(response)
        store.last_error = error.copy()
        raise Error("Multipart completion failed: " + error.code)
    if nodes[0].name != "CompleteMultipartUploadResult":
        raise Error("Unexpected multipart completion response")
    var etag = child_text(nodes, 0, "ETag")
    if not etag:
        raise Error("Completion response has no ETag")
    return PutResult(etag, get_header(response.headers, "x-amz-version-id"))


def abort(
    mut store: S3Store, bucket: String, key: String, upload_id: String
) raises:
    if not upload_id:
        raise Error("UploadId required")
    var query: List[Field] = [Field("uploadId", upload_id)]
    _ = store.request(
        "DELETE", bucket, key, query, List[Field](), List[UInt8]()
    )


def multipart_upload_file(
    mut store: S3Store,
    bucket: String,
    key: String,
    source: String,
    part_size: Int = 8 * 1024 * 1024,
    options: PutOptions = PutOptions(),
) raises -> PutResult:
    # Bound the convenience helper's RAM use; low-level UploadPart is more flexible.
    if part_size < 5 * 1024 * 1024 or part_size > 64 * 1024 * 1024:
        raise Error("File helper part_size must be 5..64 MiB")
    var file = NativeFile(source)
    var size = file.length()
    if size == 0:
        return store.put(bucket, key, List[UInt8](), options)
    var count = (size - 1) // part_size + 1
    if count > 10000:
        raise Error("Multipart upload exceeds 10000 parts")
    var upload_id = initiate(store, bucket, key, options)
    var parts = List[CompletedPart]()
    try:
        for number in range(1, count + 1):
            var length = min(part_size, size - (number - 1) * part_size)
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
                    raise Error("Multipart source changed or cannot be read")
                offset += Int(n)
            parts.append(
                upload_part(store, bucket, key, upload_id, number, buffer)
            )
        return complete(store, bucket, key, upload_id, parts)
    except e:
        var original_error = store.last_error.copy()
        try:
            abort(store, bucket, key, upload_id)
        except:
            store.last_error = original_error^
            raise Error(
                "Multipart transfer failed and abort failed; orphan upload ID: "
                + upload_id
            )
        store.last_error = original_error^
        raise e^
