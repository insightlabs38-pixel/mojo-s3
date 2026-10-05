"""S3 backend with buffered CRUD, listing, ranges, presigning, and retries."""
from std.collections import List
from std.time import sleep
from std.ffi import external_call
from mojo_s3.retry import (
    retryable_status,
    retryable_transport,
    backoff_ms,
    random_u32,
    retry_after_ms,
)
from mojo_s3.files import NativeFile, hash_file, digest_file
from mojo_s3.http import CurlTransport, HttpRequest, HttpResponse
from mojo_s3.protocol import (
    Field,
    address,
    canonical_query,
    get_header,
    uri_encode,
)
from mojo_s3.signing import sign, Credentials
from mojo_s3.crypto import sha256_hex, sha256, base64_encode, hex_encode
from mojo_s3.config import S3Config, utc_timestamp, utc_seconds
from mojo_s3.errors import S3Error, parse_s3_error
from mojo_s3.objects import (
    ObjectStore,
    PutOptions,
    ListOptions,
    ObjectRange,
    ObjectMetadata,
    ObjectInfo,
    GetResult,
    PutResult,
    ListResult,
    ReadOptions,
    CopyOptions,
    CopyResult,
    ObjectIdentifier,
    BatchDeleteResult,
)
from mojo_s3.xml import parse_xml, child_text
from mojo_s3.checksums import checksum_digest, supplied_checksum, full_checksum
from mojo_s3.options import (
    put_headers,
    copy_source,
    delete_manifest,
    parse_delete_result,
    validate_delete_result,
)
from mojo_s3.crypto import bytes_of, content_md5


def decimal(value: String) raises -> Int:
    if not value or value.byte_length() > 19:
        raise Error("Missing or invalid integer in S3 response")
    var result = 0
    for b in value.as_bytes():
        if (
            b < 48
            or b > 57
            or result > (9223372036854775807 - Int(b - 48)) // 10
        ):
            raise Error("Invalid integer in S3 response")
        result = result * 10 + Int(b - 48)
    return result


def unhex(b: UInt8) raises -> UInt8:
    if b >= 48 and b <= 57:
        return b - 48
    if b >= 65 and b <= 70:
        return b - 55
    if b >= 97 and b <= 102:
        return b - 87
    raise Error("Invalid percent encoding in S3 response")


def decode_key(value: String) raises -> String:
    var bytes = List[UInt8]()
    var i = 0
    while i < value.byte_length():
        var b = value.as_bytes()[i]
        if b == 37:
            if i + 2 >= value.byte_length():
                raise Error("Truncated percent encoding")
            bytes.append(
                unhex(value.as_bytes()[i + 1]) * 16
                + unhex(value.as_bytes()[i + 2])
            )
            i += 3
        elif b == 43:
            # S3 encoded listing fields use form URL decoding, as botocore's
            # unquote_plus does. A literal '+' is represented by '%2B'.
            bytes.append(32)
            i += 1
        else:
            bytes.append(b)
            i += 1
    return String(
        from_utf8=Span(unsafe_ptr=bytes.unsafe_ptr(), length=len(bytes))
    )


def metadata_of(response: HttpResponse) raises -> ObjectMetadata:
    var metadata = List[Field]()
    for h in response.headers:
        if h.name.startswith("x-amz-meta-"):
            metadata.append(Field(String(h.name[byte=11:]), h.value))
    var checksum = supplied_checksum(response.headers)
    var kind = get_header(response.headers, "x-amz-checksum-type")
    var state = (
        "absent" if not checksum.value else "composite" if kind == "COMPOSITE"
        or (
            not kind and "-" in checksum.value
        ) else "unverified" if full_checksum(
            response.headers
        ).value else "unsupported"
    )
    return ObjectMetadata(
        decimal(get_header(response.headers, "content-length")),
        get_header(response.headers, "etag"),
        get_header(response.headers, "content-type"),
        get_header(response.headers, "x-amz-version-id"),
        metadata^,
        checksum.value,
        checksum.name,
        False,
        kind,
        state,
    )


def validate_range_response(
    requested: ObjectRange, response: HttpResponse
) raises -> ObjectMetadata:
    """Validate status, Content-Range and exact body length before accepting bytes."""
    requested.validate()
    if response.status != 206:
        raise Error("S3 server ignored Range request")
    var range = get_header(response.headers, "content-range")
    if not range.startswith("bytes "):
        raise Error("Missing Content-Range")
    var dash = range.find("-")
    var slash = range.find("/")
    if dash <= 6 or slash <= dash:
        raise Error("Invalid Content-Range")
    var start = decimal(String(range[byte=6:dash]))
    var end = decimal(String(range[byte = dash + 1 : slash]))
    var total = decimal(String(range[byte = slash + 1 :]))
    var expected_start = (
        max(0, total - requested.suffix_length) if requested.suffix_length
        > 0 else requested.start
    )
    var expected_end = (
        total - 1 if requested.suffix_length > 0
        or requested.end < 0 else min(requested.end, total - 1)
    )
    var metadata = metadata_of(response)
    if (
        start != expected_start
        or end != expected_end
        or end < start
        or end >= total
        or end - start + 1 != len(response.body)
        or metadata.size != len(response.body)
    ):
        raise Error("S3 range response does not match requested bytes")
    metadata.size = total
    return metadata^


def full_sha256_checksum(response: HttpResponse) -> String:
    """Return only a whole-object digest that can be checked against body bytes."""
    var supplied = get_header(response.headers, "x-amz-checksum-sha256")
    var kind = get_header(response.headers, "x-amz-checksum-type")
    if kind == "COMPOSITE" or (not kind and supplied.find("-") >= 0):
        return ""
    if kind and kind != "FULL_OBJECT":
        return ""
    return supplied


struct S3Store(ObjectStore):
    var config: S3Config
    var transport: CurlTransport
    var last_error: Optional[S3Error]

    def __init__(out self, config: S3Config) raises:
        self.config = config.copy()
        self.transport = CurlTransport()
        self.last_error = None

    def __init__(out self, config: S3Config, var transport: CurlTransport):
        self.config = config.copy()
        self.transport = transport^
        self.last_error = None

    def timestamp(self) raises -> String:
        if self.config.fixed_timestamp:
            return self.config.fixed_timestamp
        return utc_timestamp()

    def request(
        mut self,
        method: String,
        bucket: String,
        key: String,
        query: List[Field],
        extra_headers: List[Field],
        body: List[UInt8],
        retry_safe: Bool = True,
        payload_hash_override: String = "",
        download_fd: Int32 = -1,
        upload_fd: Int32 = -1,
        upload_length: Int = 0,
        upload_offset: Int64 = 0,
    ) raises -> HttpResponse:
        self.last_error = None
        var a = address(
            self.config.endpoint, bucket, key, self.config.virtual_host
        )
        var url = a.url
        var q = canonical_query(query)
        if q:
            url += "?" + q
        var payload_hash = (
            payload_hash_override if payload_hash_override else sha256_hex(body)
        )
        for attempt in range(self.config.max_attempts):
            var credentials: Credentials
            try:
                credentials = self.config.credential_snapshot()
            except e:
                self.last_error = (
                    self.config.credential_cache.source.last_error.copy()
                )
                raise e^
            var timestamp = self.timestamp()
            var headers = extra_headers.copy()
            headers.append(Field("host", a.host))
            headers.append(Field("x-amz-date", timestamp))
            headers.append(Field("x-amz-content-sha256", payload_hash))
            if credentials.session_token:
                headers.append(
                    Field(
                        "x-amz-security-token",
                        credentials.session_token,
                    )
                )
            var signature = sign(
                credentials,
                self.config.region,
                "s3",
                method,
                a.path,
                query,
                headers,
                payload_hash,
                timestamp,
            )
            headers.append(Field("authorization", signature.authorization))
            headers.append(Field("user-agent", "mojo-s3/0.1.0-dev"))
            if download_fd >= 0:
                if (
                    external_call["lseek", Int64](
                        download_fd, Int64(0), Int32(0)
                    )
                    < 0
                    or external_call["ftruncate", Int32](download_fd, Int64(0))
                    < 0
                ):
                    raise Error("Cannot reset download file")
            if (
                upload_fd >= 0
                and external_call["lseek", Int64](upload_fd, Int64(0), Int32(0))
                < 0
            ):
                raise Error("Cannot rewind upload file")
            var response: HttpResponse
            try:
                response = self.transport.send(
                    HttpRequest(method, url, headers^, body.copy()),
                    download_fd,
                    upload_fd,
                    upload_length,
                    upload_offset,
                )
            except e:
                var code = self.transport.last_code
                self.last_error = S3Error(
                    0,
                    "Curl" + String(code),
                    "Native HTTP transport failure",
                    "",
                    "",
                    "",
                    "Timeout" if code == 28 else "TransportFailure",
                    attempts=attempt + 1,
                    retry_exhausted=retry_safe
                    and retryable_transport(code)
                    and attempt + 1 == self.config.max_attempts,
                )
                if (
                    retry_safe
                    and retryable_transport(code)
                    and attempt + 1 < self.config.max_attempts
                ):
                    if self.config.retry_base_ms:
                        sleep(
                            Float64(
                                backoff_ms(
                                    attempt,
                                    self.config.retry_base_ms,
                                    random_u32(),
                                )
                            )
                            / 1000.0
                        )
                    continue
                raise e^
            if response.status >= 200 and response.status < 300:
                self.last_error = None
                return response^
            if download_fd >= 0 and not len(response.body):
                # Error XML was written only to the uncommitted temporary file.
                var error_body = List[UInt8](length=65536, fill=0)
                var n = external_call["pread", Int64](
                    download_fd, error_body.unsafe_ptr(), Int(65536), Int64(0)
                )
                if n > 0:
                    error_body.shrink(Int(n))
                    response.body = error_body^
            var error = parse_s3_error(response)
            var retryable = retryable_status(response.status, error.code)
            error.attempts = attempt + 1
            error.retry_exhausted = (
                retry_safe
                and retryable
                and attempt + 1 == self.config.max_attempts
            )
            self.last_error = error.copy()
            if (
                retry_safe
                and retryable
                and attempt + 1 < self.config.max_attempts
            ):
                var delay_ms = backoff_ms(
                    attempt, self.config.retry_base_ms, random_u32()
                ) if self.config.retry_base_ms else 0
                var retry_after = get_header(response.headers, "retry-after")
                if retry_after:
                    delay_ms = max(
                        delay_ms, retry_after_ms(retry_after, utc_seconds())
                    )
                if delay_ms:
                    sleep(Float64(delay_ms) / 1000.0)
                continue
            raise Error(
                error.category
                + " (HTTP "
                + String(error.status)
                + ", S3 "
                + error.code
                + ")"
            )
        raise Error("Retry attempts exhausted")

    def check_checksum(
        mut self, response: HttpResponse, expected: String
    ) raises -> Bool:
        var supplied = full_checksum(response.headers).value
        if not supplied:
            return False
        if supplied != expected:
            self.last_error = S3Error(
                response.status,
                "ChecksumMismatch",
                "S3 full-object checksum mismatch",
                get_header(response.headers, "x-amz-request-id"),
                "",
                "",
                "DataIntegrity",
            )
            raise Error("S3 full-object checksum mismatch")
        return True

    def put(
        mut self,
        bucket: String,
        key: String,
        data: List[UInt8],
        options: PutOptions = PutOptions(),
    ) raises -> PutResult:
        var headers = put_headers(options)
        if self.config.request_checksums:
            headers.append(
                Field(
                    "x-amz-checksum-" + self.config.checksum_algorithm,
                    base64_encode(
                        checksum_digest(data, self.config.checksum_algorithm)
                    ),
                )
            )
        var response = self.request(
            "PUT", bucket, key, List[Field](), headers, data
        )
        return PutResult(
            get_header(response.headers, "etag"),
            get_header(response.headers, "x-amz-version-id"),
        )

    def get(mut self, bucket: String, key: String) raises -> GetResult:
        return self.get(bucket, key, ReadOptions())

    def get(
        mut self, bucket: String, key: String, options: ReadOptions
    ) raises -> GetResult:
        var headers = options.headers()
        if self.config.request_checksums:
            headers.append(Field("x-amz-checksum-mode", "ENABLED"))
        var response = self.request(
            "GET", bucket, key, options.query(), headers, List[UInt8]()
        )
        var metadata = metadata_of(response)
        if len(response.body) != metadata.size:
            raise Error("S3 download content-length mismatch")
        if full_checksum(response.headers).value:
            metadata.checksum_verified = self.check_checksum(
                response,
                base64_encode(
                    checksum_digest(response.body, metadata.checksum_algorithm)
                ),
            )
            metadata.checksum_state = "verified"
        var data = response.body^
        response.body = List[UInt8]()
        return GetResult(data^, metadata^)

    def head(mut self, bucket: String, key: String) raises -> ObjectMetadata:
        return self.head(bucket, key, ReadOptions())

    def head(
        mut self, bucket: String, key: String, options: ReadOptions
    ) raises -> ObjectMetadata:
        var headers = options.headers()
        if self.config.request_checksums:
            headers.append(Field("x-amz-checksum-mode", "ENABLED"))
        return metadata_of(
            self.request(
                "HEAD", bucket, key, options.query(), headers, List[UInt8]()
            )
        )

    def exists(mut self, bucket: String, key: String) raises -> Bool:
        try:
            _ = self.head(bucket, key)
            return True
        except e:
            if (
                self.last_error
                and self.last_error.value().category == "NotFound"
            ):
                return False
            raise e^

    def delete(mut self, bucket: String, key: String) raises:
        self.delete(bucket, key, ReadOptions())

    def delete(
        mut self, bucket: String, key: String, options: ReadOptions
    ) raises:
        if len(options.conditions.headers()):
            raise Error("DELETE conditions are not supported by this API")
        _ = self.request(
            "DELETE",
            bucket,
            key,
            options.query(),
            options.headers(),
            List[UInt8](),
        )

    def head_bucket(mut self, bucket: String) raises:
        _ = self.request(
            "HEAD", bucket, "", List[Field](), List[Field](), List[UInt8]()
        )

    def bucket_exists(mut self, bucket: String) raises -> Bool:
        try:
            self.head_bucket(bucket)
            return True
        except e:
            if (
                self.last_error
                and self.last_error.value().category == "NotFound"
            ):
                return False
            raise e^

    def copy_object(
        mut self,
        source_bucket: String,
        source_key: String,
        bucket: String,
        key: String,
        options: CopyOptions = CopyOptions(),
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
        if options.tagging_directive == "COPY" and len(
            options.destination.tags
        ):
            raise Error("Destination tags require tagging directive REPLACE")
        var headers = put_headers(options.destination, False)
        headers.append(
            Field(
                "x-amz-copy-source",
                copy_source(
                    source_bucket, source_key, options.source_version_id
                ),
            )
        )
        headers.append(
            Field("x-amz-metadata-directive", options.metadata_directive)
        )
        headers.append(
            Field("x-amz-tagging-directive", options.tagging_directive)
        )
        for field in options.source_conditions.headers("x-amz-copy-source-"):
            headers.append(field.copy())
        # CopyObject is limited to 5 GiB by S3; larger copies require multipart copy.
        var response = self.request(
            "PUT", bucket, key, List[Field](), headers, List[UInt8](), False
        )
        var nodes = parse_xml(
            String(
                from_utf8=Span(
                    unsafe_ptr=response.body.unsafe_ptr(),
                    length=len(response.body),
                )
            )
        )
        if nodes[0].name == "Error":
            self.last_error = parse_s3_error(response)
            raise Error("CopyObject returned an embedded S3 error")
        if nodes[0].name != "CopyObjectResult" or not child_text(
            nodes, 0, "ETag"
        ):
            raise Error("Malformed CopyObject result")
        return CopyResult(
            child_text(nodes, 0, "ETag"),
            child_text(nodes, 0, "LastModified"),
            get_header(response.headers, "x-amz-version-id"),
            get_header(response.headers, "x-amz-copy-source-version-id"),
        )

    def delete_objects(
        mut self, bucket: String, objects: List[ObjectIdentifier]
    ) raises -> BatchDeleteResult:
        var body = bytes_of(delete_manifest(objects))
        var headers: List[Field] = [
            Field("content-type", "application/xml"),
            Field("content-md5", content_md5(body)),
        ]
        var query: List[Field] = [Field("delete", "")]
        # Repeating versioned deletions can mutate delete-marker state; no retry.
        var response = self.request(
            "POST", bucket, "", query, headers, body, False
        )
        var result = parse_delete_result(
            String(
                from_utf8=Span(
                    unsafe_ptr=response.body.unsafe_ptr(),
                    length=len(response.body),
                )
            )
        )
        validate_delete_result(objects, result)
        return result^

    def list(
        mut self, bucket: String, options: ListOptions = ListOptions()
    ) raises -> ListResult:
        if options.max_keys < 1 or options.max_keys > 1000:
            raise Error("max_keys must be 1..1000")
        var query: List[Field] = [
            Field("list-type", "2"),
            Field("encoding-type", "url"),
            Field("max-keys", String(options.max_keys)),
        ]
        if options.prefix:
            query.append(Field("prefix", options.prefix))
        if options.delimiter:
            query.append(Field("delimiter", options.delimiter))
        if options.continuation_token:
            query.append(
                Field("continuation-token", options.continuation_token)
            )
        var response = self.request(
            "GET", bucket, "", query, List[Field](), List[UInt8]()
        )
        var text = String(
            from_utf8=Span(
                unsafe_ptr=response.body.unsafe_ptr(), length=len(response.body)
            )
        )
        var nodes = parse_xml(text)
        if nodes[0].name != "ListBucketResult":
            raise Error("Unexpected S3 listing XML root")
        var encoded = child_text(nodes, 0, "EncodingType") == "url"
        var objects = List[ObjectInfo]()
        var prefixes = List[String]()
        for i in range(len(nodes)):
            if nodes[i].parent != 0:
                continue
            if nodes[i].name == "Contents":
                var key = child_text(nodes, i, "Key")
                if encoded:
                    key = decode_key(key)
                objects.append(
                    ObjectInfo(
                        key,
                        decimal(child_text(nodes, i, "Size")),
                        child_text(nodes, i, "ETag"),
                        child_text(nodes, i, "LastModified"),
                    )
                )
            elif nodes[i].name == "CommonPrefixes":
                var prefix = child_text(nodes, i, "Prefix")
                prefixes.append(decode_key(prefix) if encoded else prefix)
        var truncated = child_text(nodes, 0, "IsTruncated")
        if truncated != "true" and truncated != "false":
            raise Error("Missing or invalid listing truncation state")
        var token = child_text(nodes, 0, "NextContinuationToken")
        if truncated == "true" and not token:
            raise Error("Truncated S3 listing has no continuation token")
        return ListResult(objects^, prefixes^, truncated == "true", token)

    def get_range(
        mut self, bucket: String, key: String, requested: ObjectRange
    ) raises -> GetResult:
        return self.get_range(bucket, key, requested, ReadOptions())

    def get_range(
        mut self,
        bucket: String,
        key: String,
        requested: ObjectRange,
        options: ReadOptions,
    ) raises -> GetResult:
        requested.validate()
        var headers = options.headers()
        headers.append(Field("range", requested.header()))
        var response = self.request(
            "GET", bucket, key, options.query(), headers, List[UInt8]()
        )
        var metadata = validate_range_response(requested, response)
        var data = response.body^
        response.body = List[UInt8]()
        return GetResult(data^, metadata^)

    def presign(
        mut self,
        method: String,
        bucket: String,
        key: String,
        expires: Int = 900,
        extra_headers: List[Field] = List[Field](),
    ) raises -> String:
        if (
            (method != "GET" and method != "PUT")
            or expires < 1
            or expires > 604800
        ):
            raise Error(
                "Presign supports GET/PUT and expiration 1..604800 seconds"
            )
        var credentials = self.config.credential_snapshot()
        if self.config.credential_cache.snapshot:
            if (
                expires
                > self.config.credential_cache.snapshot.value().expiration
                - Int(utc_seconds())
            ):
                raise Error(
                    "Presign duration exceeds workload credential expiration"
                )
        var a = address(
            self.config.endpoint, bucket, key, self.config.virtual_host
        )
        var timestamp = self.timestamp()
        var scope = (
            String(timestamp[byte=0:8])
            + "/"
            + self.config.region
            + "/s3/aws4_request"
        )
        var headers = extra_headers.copy()
        headers.append(Field("host", a.host))
        var query: List[Field] = [
            Field("X-Amz-Algorithm", "AWS4-HMAC-SHA256"),
            Field(
                "X-Amz-Credential",
                credentials.access_key + "/" + scope,
            ),
            Field("X-Amz-Date", timestamp),
            Field("X-Amz-Expires", String(expires)),
        ]
        # Header names are canonicalized using the same ordinary signer.
        var initial = sign(
            credentials,
            self.config.region,
            "s3",
            method,
            a.path,
            query,
            headers,
            "UNSIGNED-PAYLOAD",
            timestamp,
        )
        query.append(Field("X-Amz-SignedHeaders", initial.signed_headers))
        if credentials.session_token:
            query.append(
                Field(
                    "X-Amz-Security-Token",
                    credentials.session_token,
                )
            )
        var result = sign(
            credentials,
            self.config.region,
            "s3",
            method,
            a.path,
            query,
            headers,
            "UNSIGNED-PAYLOAD",
            timestamp,
        )
        query.append(Field("X-Amz-Signature", result.signature))
        return a.url + "?" + canonical_query(query)

    def download_file(
        mut self, bucket: String, key: String, destination: String
    ) raises -> ObjectMetadata:
        var file = NativeFile(destination, True)
        var headers = List[Field]()
        if self.config.request_checksums:
            headers.append(Field("x-amz-checksum-mode", "ENABLED"))
        var response = self.request(
            "GET",
            bucket,
            key,
            List[Field](),
            headers,
            List[UInt8](),
            True,
            "",
            file.fd,
        )
        var metadata = metadata_of(response)
        if metadata.size != self.transport.last_response_bytes:
            raise Error("Streamed download content-length mismatch")
        if full_checksum(response.headers).value:
            metadata.checksum_verified = self.check_checksum(
                response,
                base64_encode(digest_file(file, metadata.checksum_algorithm)),
            )
            metadata.checksum_state = "verified"
        file.commit(destination)
        return metadata^

    def upload_file(
        mut self,
        bucket: String,
        key: String,
        source: String,
        options: PutOptions = PutOptions(),
    ) raises -> PutResult:
        var file = NativeFile(source)
        var length = file.length()
        var digest = digest_file(file)
        var hash = hex_encode(digest)
        var headers = put_headers(options)
        if self.config.request_checksums:
            headers.append(
                Field(
                    "x-amz-checksum-" + self.config.checksum_algorithm,
                    base64_encode(
                        digest_file(file, self.config.checksum_algorithm)
                    ),
                )
            )
        var response = self.request(
            "PUT",
            bucket,
            key,
            List[Field](),
            headers,
            List[UInt8](),
            True,
            hash,
            -1,
            file.fd,
            length,
        )
        _ = file
        return PutResult(
            get_header(response.headers, "etag"),
            get_header(response.headers, "x-amz-version-id"),
        )
