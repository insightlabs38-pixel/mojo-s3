"""Explicit/environment configuration and a single UTC clock entry point."""
from std.os import getenv
from std.ffi import external_call
from std.memory import Pointer
from std.collections import List
from mojo_s3.signing import Credentials


struct S3Config(Copyable, Movable):
    var endpoint: String
    var region: String
    var credentials: Credentials
    var virtual_host: Bool
    var fixed_timestamp: String
    var max_attempts: Int
    var retry_base_ms: Int
    var request_checksums: Bool

    def __init__(
        out self,
        endpoint: String,
        region: String,
        credentials: Credentials,
        virtual_host: Bool = False,
        fixed_timestamp: String = "",
        max_attempts: Int = 3,
        retry_base_ms: Int = 100,
        request_checksums: Bool = False,
    ) raises:
        if (
            max_attempts < 1
            or max_attempts > 10
            or retry_base_ms < 0
            or retry_base_ms > 60000
        ):
            raise Error("Invalid retry configuration")
        self.endpoint = endpoint
        self.region = region
        self.credentials = credentials.copy()
        self.virtual_host = virtual_host
        self.fixed_timestamp = fixed_timestamp
        self.max_attempts = max_attempts
        self.retry_base_ms = retry_base_ms
        self.request_checksums = request_checksums

    @staticmethod
    def from_env() raises -> Self:
        return Self(
            getenv("S3_ENDPOINT", "https://s3.amazonaws.com"),
            getenv("S3_REGION", getenv("AWS_REGION", "us-east-1")),
            Credentials(
                getenv("S3_ACCESS_KEY", getenv("AWS_ACCESS_KEY_ID")),
                getenv("S3_SECRET_KEY", getenv("AWS_SECRET_ACCESS_KEY")),
                getenv("S3_SESSION_TOKEN", getenv("AWS_SESSION_TOKEN")),
            ),
            getenv("S3_FORCE_PATH_STYLE", "true") == "false",
        )


comptime Raw = Pointer[UInt8, MutUntrackedOrigin]


def utc_seconds() raises -> Int64:
    var seconds = external_call["time", Int64](Optional[Raw](None))
    if seconds == -1:
        raise Error("System clock unavailable")
    return seconds


def utc_timestamp() raises -> String:
    var seconds = utc_seconds()
    # Opaque libc tm storage; 128 bytes exceeds Linux struct tm size.
    var tm = List[UInt8](length=128, fill=0)
    if not external_call["gmtime_r", Optional[Raw]](
        Pointer(to=seconds), tm.unsafe_ptr()
    ):
        raise Error("Cannot convert system UTC time")
    var result = List[UInt8](length=32, fill=0)
    var fmt = "%Y%m%dT%H%M%SZ"
    var n = external_call["strftime", Int](
        result.unsafe_ptr(), Int(32), fmt.as_c_string_span(), tm.unsafe_ptr()
    )
    if n != 16:
        raise Error("Cannot format signing timestamp")
    return String(from_utf8=Span(unsafe_ptr=result.unsafe_ptr(), length=n))
