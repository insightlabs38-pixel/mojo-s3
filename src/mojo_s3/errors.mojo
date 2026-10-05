"""Structured S3 errors retained by the client when a Mojo Error is raised."""
from mojo_s3.http import HttpResponse
from mojo_s3.protocol import get_header
from mojo_s3.xml import parse_xml, child_text


struct S3Error(Copyable, Movable):
    var status: Int
    var code: String
    var message: String
    var request_id: String
    var host_id: String
    var resource: String
    var category: String
    var bucket_region: String
    var attempts: Int
    var retry_exhausted: Bool

    def __init__(
        out self,
        status: Int,
        code: String,
        message: String,
        request_id: String,
        host_id: String,
        resource: String,
        category: String,
        bucket_region: String = "",
        attempts: Int = 0,
        retry_exhausted: Bool = False,
    ):
        self.status = status
        self.code = code
        self.message = message
        self.request_id = request_id
        self.host_id = host_id
        self.resource = resource
        self.category = category
        self.bucket_region = bucket_region
        self.attempts = attempts
        self.retry_exhausted = retry_exhausted


def error_category(status: Int, code: String) -> String:
    if (
        status == 301
        or status == 307
        or code == "AuthorizationHeaderMalformed"
        or code == "PermanentRedirect"
        or code == "IncorrectEndpoint"
    ):
        return "RegionMismatch"
    if status == 304:
        return "NotModified"
    if status == 404:
        return "NotFound"
    if code == "SignatureDoesNotMatch":
        return "SignatureMismatch"
    if code == "RequestExpired" or code == "ExpiredToken":
        return "ExpiredRequest"
    if status == 401 or status == 403:
        return "AccessDenied"
    if status == 416:
        return "InvalidRange"
    if status == 412:
        return "PreconditionFailed"
    if (
        status >= 500
        or code == "InternalError"
        or code == "ServiceUnavailable"
        or code == "SlowDown"
    ):
        return "ServerFailure"
    return "InvalidRequest"


def parse_s3_error(response: HttpResponse) -> S3Error:
    var code = String()
    var message = String()
    var request_id = get_header(response.headers, "x-amz-request-id")
    var host_id = get_header(response.headers, "x-amz-id-2")
    var resource = String()
    if len(response.body):
        try:
            var text = String(
                from_utf8=Span(
                    unsafe_ptr=response.body.unsafe_ptr(),
                    length=len(response.body),
                )
            )
            var nodes = parse_xml(text)
            if nodes[0].name == "Error":
                code = child_text(nodes, 0, "Code")
                message = child_text(nodes, 0, "Message")
                resource = child_text(nodes, 0, "Resource")
                var id = child_text(nodes, 0, "RequestId")
                if id:
                    request_id = id
                id = child_text(nodes, 0, "HostId")
                if id:
                    host_id = id
        except:
            # Preserve HTTP failure even if a proxy returned HTML/malformed XML.
            pass
    return S3Error(
        response.status,
        code,
        message,
        request_id,
        host_id,
        resource,
        error_category(response.status, code),
        get_header(response.headers, "x-amz-bucket-region"),
    )
