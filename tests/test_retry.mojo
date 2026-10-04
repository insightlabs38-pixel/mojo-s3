from std.testing import assert_true, assert_false, assert_equal
from mojo_s3.retry import (
    retryable_status,
    retryable_transport,
    backoff_ms,
    retry_after_ms,
)


def main() raises:
    for status in [408, 429, 500, 502, 503, 504]:
        assert_true(retryable_status(status, ""))
    for status in [400, 401, 403, 404, 409, 412, 416]:
        assert_false(retryable_status(status, ""))
    assert_true(retryable_status(400, "SlowDown"))
    assert_true(retryable_transport(56))
    assert_false(
        retryable_transport(60)
    )  # certificate validation must not retry
    assert_false(retryable_transport(23))  # bounded-buffer write failure
    assert_equal(backoff_ms(0, 100, 100), 100)
    assert_equal(backoff_ms(1, 100, 200), 200)
    assert_true(backoff_ms(10, 60000, 4294967295) <= 60000)
    assert_equal(backoff_ms(4, 0, 42), 0)
    assert_equal(retry_after_ms("120", 0), 60000)
    assert_equal(retry_after_ms("999999999999999999999999999", 0), 60000)
    assert_equal(retry_after_ms("0", 0), 0)
    assert_equal(retry_after_ms("-1", 0), 0)
    assert_equal(
        retry_after_ms("Sun, 06 Nov 1994 08:49:37 GMT", 784111770), 7000
    )
    assert_equal(
        retry_after_ms("Sunday, 06-Nov-94 08:49:37 GMT", 784111770), 7000
    )
    assert_equal(retry_after_ms("Sun Nov  6 08:49:37 1994", 784111770), 7000)
    assert_equal(retry_after_ms("Sun, 06 Nov 1994 08:49:37 GMT", 784111778), 0)
    assert_equal(retry_after_ms("garbage", 0), 0)
    print(
        "retry classification, jitter bounds, exponential ceilings, and zero-delay hooks passed"
    )
