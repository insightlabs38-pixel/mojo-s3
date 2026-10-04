"""Pure retry decisions and bounded full-jitter exponential backoff."""
from std.ffi import external_call
from std.memory import Pointer


def retryable_status(status: Int, code: String) -> Bool:
    return (
        status == 408
        or status == 429
        or status == 500
        or status == 502
        or status == 503
        or status == 504
        or code == "SlowDown"
    )


def retryable_transport(code: Int) -> Bool:
    return (
        code == 7
        or code == 18
        or code == 28
        or code == 52
        or code == 55
        or code == 56
    )


def backoff_ms(attempt: Int, base_ms: Int, entropy: UInt32) -> Int:
    var ceiling = min(base_ms * (1 << min(attempt, 10)), 60000)
    return Int(UInt64(entropy) % UInt64(ceiling + 1))


def random_u32() raises -> UInt32:
    var value = UInt32(0)
    if external_call["RAND_bytes", Int32](Pointer(to=value), Int32(4)) != 1:
        raise Error("Cannot obtain retry entropy")
    return value


def retry_after_ms(value: String, now_seconds: Int64) -> Int:
    """Parse delta seconds or HTTP dates with libcurl; clamp waits to 60 seconds."""
    var text = String(value.strip())
    if not text or text.find("\x00") >= 0:
        return 0
    var numeric = True
    var seconds = 0
    for b in text.as_bytes():
        if b < 48 or b > 57:
            numeric = False
            break
        # Saturate during parsing: even unbounded decimal input cannot overflow.
        seconds = min(seconds * 10 + Int(b - 48), 60)
    if numeric:
        return seconds * 1000
    var deadline = external_call["curl_getdate", Int64](
        text.as_c_string_span(),
        Optional[Pointer[Int64, MutUntrackedOrigin]](None),
    )
    if deadline < 0 or now_seconds < 0 or deadline <= now_seconds:
        return 0
    return Int(min(deadline - now_seconds, Int64(60))) * 1000
