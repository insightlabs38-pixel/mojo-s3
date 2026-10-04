"""Synchronous native libcurl transport; owns and reuses one easy handle.

A transport is single-owner and must not be used concurrently. Redirects are
never followed: forwarding signed requests can disclose credentials.
"""
from std.collections import List
from std.ffi import external_call
from std.memory import Pointer
from mojo_s3.files import errno_value
from mojo_s3.protocol import Field, validate_header_name, normalize_space

comptime Raw = Pointer[UInt8, MutUntrackedOrigin]


@fieldwise_init
struct HttpRequest(Copyable, Movable):
    var method: String
    var url: String
    var headers: List[Field]
    var body: List[UInt8]


@fieldwise_init
struct HttpResponse(Copyable, Movable):
    var status: Int
    var headers: List[Field]
    var body: List[UInt8]


struct Capture(Movable):
    var data: List[UInt8]
    var limit: Int
    var overflow: Bool
    var fd: Int32
    var received: Int

    def __init__(out self, limit: Int, fd: Int32 = -1):
        self.data = List[UInt8]()
        self.limit = limit
        self.overflow = False
        self.fd = fd
        self.received = 0


def receive(
    data: Raw,
    size: UInt,
    count: UInt,
    context: Pointer[Capture, MutUntrackedOrigin],
) abi("C") -> UInt:
    # libcurl uses size=1, but check multiplication for ABI robustness.
    if size and count > UInt(-1) // size:
        return 0
    var n = size * count
    if n > UInt(context[].limit - context[].received):
        context[].overflow = True
        return 0
    if context[].fd >= 0:
        var offset = 0
        while offset < Int(n):
            var wrote = external_call["write", Int64](
                Int(context[].fd), data.unsafe_offset(offset), Int(n) - offset
            )
            if wrote < 0 and errno_value() == 4:
                continue
            if wrote <= 0:
                return 0
            offset += Int(wrote)
    else:
        for i in range(Int(n)):
            context[].data.append(data[unsafe_offset=i])
    context[].received += Int(n)
    return n


def provide(
    data: Raw,
    size: UInt,
    count: UInt,
    context: Pointer[Int32, MutUntrackedOrigin],
) abi("C") -> UInt:
    if size and count > UInt(-1) // size:
        return UInt(0x10000000)  # CURL_READFUNC_ABORT
    while True:
        var n = external_call["read", Int64](
            Int(context[]), data, Int(size * count)
        )
        if n < 0:
            if errno_value() == 4:
                continue
            return UInt(0x10000000)
        return UInt(n)


struct CurlTransport(Movable):
    var handle: Raw
    var timeout_ms: Int
    var connect_timeout_ms: Int
    var max_response_bytes: Int
    var verify_tls: Bool
    var last_response_bytes: Int
    var last_code: Int
    var ca_bundle: String

    def __init__(
        out self,
        timeout_ms: Int = 30000,
        connect_timeout_ms: Int = 5000,
        max_response_bytes: Int = 64 * 1024 * 1024,
        verify_tls: Bool = True,
        ca_bundle: String = "",
    ) raises:
        if timeout_ms <= 0 or connect_timeout_ms <= 0 or max_response_bytes < 0:
            raise Error("Invalid HTTP limits")
        if external_call["curl_global_init", Int32](Int(3)) != 0:
            raise Error("libcurl initialization failed")
        var h = external_call["curl_easy_init", Optional[Raw]]()
        if not h:
            raise Error("libcurl allocation failed")
        self.handle = h.value()
        self.timeout_ms = timeout_ms
        self.connect_timeout_ms = connect_timeout_ms
        self.max_response_bytes = max_response_bytes
        self.verify_tls = verify_tls
        self.last_response_bytes = 0
        self.last_code = 0
        self.ca_bundle = ca_bundle

    def __deinit__(deinit self):
        external_call["curl_easy_cleanup", NoneType](self.handle)

    def option[T: AnyType](self, option: Int32, value: T) raises:
        var result = external_call["curl_easy_setopt", Int32, num_fixed_args=2](
            self.handle, option, value
        )
        if result != 0:
            raise Error("libcurl option failed: " + String(Int(result)))

    def send(
        mut self,
        request: HttpRequest,
        download_fd: Int32 = -1,
        upload_fd: Int32 = -1,
        upload_length: Int = 0,
    ) raises -> HttpResponse:
        external_call["curl_easy_reset", NoneType](self.handle)
        self.last_code = 0
        self.last_response_bytes = 0
        var body = Capture(
            self.max_response_bytes if download_fd < 0 else 9223372036854775807,
            download_fd,
        )
        var header_data = Capture(65536)
        var headers: Optional[Raw] = None
        try:
            for h in request.headers:
                validate_header_name(h.name)
                var line = h.name + ": " + normalize_space(h.value)
                var updated = external_call["curl_slist_append", Optional[Raw]](
                    headers, line.as_c_string_span()
                )
                if not updated:
                    raise Error("libcurl header allocation failed")
                headers = updated
            # Disable implicit Expect: 100-continue; libcurl still handles 1xx.
            var expect = "Expect:"
            var updated = external_call["curl_slist_append", Optional[Raw]](
                headers, expect.as_c_string_span()
            )
            if not updated:
                raise Error("libcurl header allocation failed")
            headers = updated
            var url = request.url
            var method = request.method
            self.option(10002, url.as_c_string_span())
            self.option(10036, method.as_c_string_span())
            self.option(10023, headers)
            self.option(20011, receive)
            self.option(10001, Pointer(to=body))
            self.option(20079, receive)
            self.option(10029, Pointer(to=header_data))
            self.option(155, self.timeout_ms)
            self.option(156, self.connect_timeout_ms)
            self.option(99, Int(1))  # NOSIGNAL
            self.option(52, Int(0))  # FOLLOWLOCATION
            self.option(234, Int(1))  # PATH_AS_IS: keys may contain /../
            if self.ca_bundle:
                var ca_bundle = self.ca_bundle
                self.option(10065, ca_bundle.as_c_string_span())
            self.option(64, Int(self.verify_tls))
            self.option(81, Int(2 if self.verify_tls else 0))
            self.option(181, Int(3))  # HTTP(S) protocols only
            # Do not request automatic content decoding: S3 bytes are opaque.
            self.option(158, Int(0))  # HTTP_CONTENT_DECODING
            var input_fd = upload_fd
            if request.method == "HEAD":
                self.option(44, Int(1))
            elif upload_fd >= 0:
                self.option(46, Int(1))  # UPLOAD
                self.option(30115, Int64(upload_length))
                self.option(20012, provide)
                self.option(10009, Pointer(to=input_fd))
            elif (
                request.method == "PUT"
                or request.method == "POST"
                or len(request.body)
            ):
                self.option(30120, Int64(len(request.body)))
                self.option(10015, request.body.unsafe_ptr())
            var code = external_call["curl_easy_perform", Int32](self.handle)
            self.last_code = Int(code)
            self.last_response_bytes = body.received
            if code != 0:
                if body.overflow or header_data.overflow:
                    raise Error("HTTP response exceeds configured buffer limit")
                # Do not include URL/headers in errors (presigned URLs are secrets).
                raise Error(
                    "HTTP transport failure (libcurl " + String(Int(code)) + ")"
                )
            var status = Int(0)
            if (
                external_call["curl_easy_getinfo", Int32, num_fixed_args=2](
                    self.handle, Int32(0x200002), Pointer(to=status)
                )
                != 0
            ):
                raise Error("Cannot read HTTP status")
            var text = String(
                from_utf8_lossy=Span(
                    unsafe_ptr=header_data.data.unsafe_ptr(),
                    length=len(header_data.data),
                )
            )
            var parsed = List[Field]()
            for line in text.splitlines():
                var s = String(line)
                if s.startswith("HTTP/"):
                    parsed.clear()
                else:
                    var colon = s.find(":")
                    if colon > 0:
                        parsed.append(
                            Field(
                                String(s[byte=0:colon]).lower(),
                                String(String(s[byte = colon + 1 :]).strip()),
                            )
                        )
            external_call["curl_slist_free_all", NoneType](headers)
            var payload = body.data^
            body.data = List[UInt8]()
            return HttpResponse(status, parsed^, payload^)
        except e:
            external_call["curl_slist_free_all", NoneType](headers)
            raise e^
