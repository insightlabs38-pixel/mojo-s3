"""Structured S3 errors retained by the client when a Mojo Error is raised."""
from mojo_s3.http import HttpResponse
from mojo_s3.protocol import get_header
from mojo_s3.xml import parse_xml, child_text


@fieldwise_init
struct S3Error(Copyable, Movable):
    var status: Int
    var code: String
    var message: String
    var request_id: String
    var host_id: String
    var resource: String
    var category: String


def error_category(status: Int, code: String) -> String:
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
    )
