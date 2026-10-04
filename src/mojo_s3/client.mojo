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
from mojo_s3.signing import sign
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
)
from mojo_s3.xml import parse_xml, child_text


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
    return ObjectMetadata(
        decimal(get_header(response.headers, "content-length")),
        get_header(response.headers, "etag"),
        get_header(response.headers, "content-type"),
        get_header(response.headers, "x-amz-version-id"),
        metadata^,
        get_header(response.headers, "x-amz-checksum-sha256"),
        "sha256" if get_header(
            response.headers, "x-amz-checksum-sha256"
        ) else "",
    )


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
            var timestamp = self.timestamp()
            var headers = extra_headers.copy()
            headers.append(Field("host", a.host))
            headers.append(Field("x-amz-date", timestamp))
            headers.append(Field("x-amz-content-sha256", payload_hash))
            if self.config.credentials.session_token:
                headers.append(
                    Field(
                        "x-amz-security-token",
                        self.config.credentials.session_token,
                    )
                )
            var signature = sign(
                self.config.credentials,
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
            self.last_error = error.copy()
            var retryable = retryable_status(response.status, error.code)
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
        var supplied = full_sha256_checksum(response)
        if not supplied:
            return False
        if supplied != expected:
            self.last_error = S3Error(
                response.status,
                "ChecksumMismatch",
                "S3 full-object SHA256 mismatch",
                get_header(response.headers, "x-amz-request-id"),
                "",
                "",
                "DataIntegrity",
            )
            raise Error("S3 full-object SHA256 checksum mismatch")
        return True

    def put(
        mut self,
        bucket: String,
        key: String,
        data: List[UInt8],
        options: PutOptions = PutOptions(),
    ) raises -> PutResult:
        var headers: List[Field] = [Field("content-type", options.content_type)]
        for m in options.metadata:
            headers.append(Field("x-amz-meta-" + m.name.lower(), m.value))
        if self.config.request_checksums:
            headers.append(
                Field("x-amz-checksum-sha256", base64_encode(sha256(data)))
            )
        var response = self.request(
            "PUT", bucket, key, List[Field](), headers, data
        )
        return PutResult(
            get_header(response.headers, "etag"),
            get_header(response.headers, "x-amz-version-id"),
        )

    def get(mut self, bucket: String, key: String) raises -> GetResult:
        var headers = List[Field]()
        if self.config.request_checksums:
            headers.append(Field("x-amz-checksum-mode", "ENABLED"))
        var response = self.request(
            "GET", bucket, key, List[Field](), headers, List[UInt8]()
        )
        var metadata = metadata_of(response)
        if len(response.body) != metadata.size:
            raise Error("S3 download content-length mismatch")
        if full_sha256_checksum(response):
            metadata.checksum_verified = self.check_checksum(
                response, base64_encode(sha256(response.body))
            )
        var data = response.body^
        response.body = List[UInt8]()
        return GetResult(data^, metadata^)

    def head(mut self, bucket: String, key: String) raises -> ObjectMetadata:
        return metadata_of(
            self.request(
                "HEAD", bucket, key, List[Field](), List[Field](), List[UInt8]()
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
        _ = self.request(
            "DELETE", bucket, key, List[Field](), List[Field](), List[UInt8]()
        )

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
        if (
            requested.start < 0
            or requested.end < -1
            or (requested.end >= 0 and requested.end < requested.start)
        ):
            raise Error("Invalid object range")
        var headers: List[Field] = [Field("range", requested.header())]
        var response = self.request(
            "GET", bucket, key, List[Field](), headers, List[UInt8]()
        )
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
        var expected_end = total - 1 if requested.end < 0 else min(
            requested.end, total - 1
        )
        var metadata = metadata_of(response)
        if (
            start != requested.start
            or end != expected_end
            or end < start
            or end >= total
            or end - start + 1 != len(response.body)
            or metadata.size != len(response.body)
        ):
            raise Error("S3 range response does not match requested bytes")
        metadata.size = total
        var data = response.body^
        response.body = List[UInt8]()
        return GetResult(data^, metadata^)

    def presign(
        self,
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
                self.config.credentials.access_key + "/" + scope,
            ),
            Field("X-Amz-Date", timestamp),
            Field("X-Amz-Expires", String(expires)),
        ]
        # Header names are canonicalized using the same ordinary signer.
        var initial = sign(
            self.config.credentials,
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
        if self.config.credentials.session_token:
            query.append(
                Field(
                    "X-Amz-Security-Token",
                    self.config.credentials.session_token,
                )
            )
        var result = sign(
            self.config.credentials,
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
        if full_sha256_checksum(response):
            metadata.checksum_verified = self.check_checksum(
                response, base64_encode(digest_file(file))
            )
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
        var headers: List[Field] = [Field("content-type", options.content_type)]
        for m in options.metadata:
            headers.append(Field("x-amz-meta-" + m.name.lower(), m.value))
        if self.config.request_checksums:
            headers.append(
                Field("x-amz-checksum-sha256", base64_encode(digest))
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
