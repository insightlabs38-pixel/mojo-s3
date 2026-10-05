"""Server-side multipart copy: no source payload enters the client."""
from std.collections import List
from mojo_s3.client import S3Store, metadata_of
from mojo_s3.objects import CopyOptions, CopyResult, ReadOptions
from mojo_s3.protocol import Field, get_header
from mojo_s3.options import copy_source
from mojo_s3.errors import parse_s3_error
from mojo_s3.xml import parse_xml, child_text
from mojo_s3.multipart import initiate, complete, abort, CompletedPart
from mojo_s3.multipart_plan import plan_multipart, MAX_PART_BYTES
from mojo_s3.tagging import get_object_tagging


def upload_part_copy(
    mut store: S3Store,
    source_bucket: String,
    source_key: String,
    bucket: String,
    key: String,
    upload_id: String,
    number: Int,
    start: Int64,
    length: Int64,
    options: CopyOptions = CopyOptions(),
) raises -> CompletedPart:
    if (
        not upload_id
        or number < 1
        or number > 10000
        or start < 0
        or length < 1
        or length > MAX_PART_BYTES
        or start > Int64(9223372036854775807) - length
    ):
        raise Error("Invalid UploadPartCopy range")
    var query: List[Field] = [
        Field("uploadId", upload_id),
        Field("partNumber", String(number)),
    ]
    var headers = options.source_conditions.headers("x-amz-copy-source-")
    headers.append(
        Field(
            "x-amz-copy-source",
            copy_source(source_bucket, source_key, options.source_version_id),
        )
    )
    headers.append(
        Field(
            "x-amz-copy-source-range",
            "bytes=" + String(start) + "-" + String(start + length - 1),
        )
    )
    if options.destination.expected_bucket_owner:
        headers.append(
            Field(
                "x-amz-expected-bucket-owner",
                options.destination.expected_bucket_owner,
            )
        )
    var response = store.request(
        "PUT", bucket, key, query, headers, List[UInt8](), True
    )
    var nodes = parse_xml(
        String(
            from_utf8=Span(
                unsafe_ptr=response.body.unsafe_ptr(), length=len(response.body)
            )
        )
    )
    if nodes[0].name == "Error":
        store.last_error = parse_s3_error(response)
        raise Error("UploadPartCopy returned an embedded S3 error")
    var etag = child_text(nodes, 0, "ETag")
    if nodes[0].name != "CopyPartResult" or not etag:
        raise Error("Malformed UploadPartCopy result")
    return CompletedPart(number, etag)


def multipart_copy_object(
    mut store: S3Store,
    source_bucket: String,
    source_key: String,
    bucket: String,
    key: String,
    options: CopyOptions = CopyOptions(),
    target_part_bytes: Int64 = 64 * 1024 * 1024,
) raises -> CopyResult:
    if (
        options.metadata_directive != "COPY"
        and options.metadata_directive != "REPLACE"
    ):
        raise Error("Copy metadata directive must be COPY or REPLACE")
    if (
        options.tagging_directive != "COPY"
        and options.tagging_directive != "REPLACE"
    ):
        raise Error("Copy tagging directive must be COPY or REPLACE")
    if options.tagging_directive == "COPY" and len(options.destination.tags):
        raise Error("Destination tags require tagging directive REPLACE")
    var reads = ReadOptions(
        options.source_version_id, options.source_conditions
    )
    var head = store.request(
        "HEAD",
        source_bucket,
        source_key,
        reads.query(),
        reads.headers(),
        List[UInt8](),
    )
    var metadata = metadata_of(head)
    if metadata.size == 0:
        return store.copy_object(
            source_bucket, source_key, bucket, key, options
        )
    if not metadata.etag:
        raise Error("Multipart copy requires source ETag identity")
    var plan = plan_multipart(Int64(metadata.size), target_part_bytes)
    var pinned = options.copy()
    pinned.source_conditions.if_match = metadata.etag
    if metadata.version_id:
        pinned.source_version_id = metadata.version_id
    var destination = options.destination.copy()
    if options.metadata_directive == "COPY":
        destination.content_type = metadata.content_type
        destination.metadata = metadata.metadata.copy()
        destination.content_disposition = get_header(
            head.headers, "content-disposition"
        )
        destination.content_encoding = get_header(
            head.headers, "content-encoding"
        )
        destination.content_language = get_header(
            head.headers, "content-language"
        )
        destination.cache_control = get_header(head.headers, "cache-control")
    # Match ordinary CopyObject tag-copy semantics; this requires GetObjectTagging.
    if options.tagging_directive == "COPY":
        destination.tags = get_object_tagging(
            store, source_bucket, source_key, pinned.source_version_id
        )
    var upload_id = initiate(store, bucket, key, destination)
    try:
        var parts = List[CompletedPart](capacity=plan.part_count)
        for number in range(1, plan.part_count + 1):
            parts.append(
                upload_part_copy(
                    store,
                    source_bucket,
                    source_key,
                    bucket,
                    key,
                    upload_id,
                    number,
                    plan.offset(number),
                    plan.length(number),
                    pinned,
                )
            )
        var result = complete(store, bucket, key, upload_id, parts)
        return CopyResult(
            result.etag, "", result.version_id, pinned.source_version_id
        )
    except e:
        var original = store.last_error.copy()
        try:
            abort(store, bucket, key, upload_id)
        except:
            store.last_error = original^
            raise Error(
                "Multipart copy failed and abort failed; orphan upload ID: "
                + upload_id
            )
        store.last_error = original^
        raise e^
