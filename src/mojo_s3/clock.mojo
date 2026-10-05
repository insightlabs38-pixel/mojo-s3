"""Native UTC signing clock, shared by S3 and STS without provider cycles."""
from std.ffi import external_call
from std.collections import List
from std.memory import Pointer

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
