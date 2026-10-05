from std.testing import assert_equal, assert_true
from mojo_s3.multipart_plan import (
    plan_multipart,
    MIN_PART_BYTES,
    MAX_PART_BYTES,
    MAX_MULTIPART_BYTES,
)


def main() raises:
    for size in [
        Int64(0),
        Int64(1),
        MIN_PART_BYTES - 1,
        MIN_PART_BYTES,
        MIN_PART_BYTES + 1,
        Int64(64 * 1024 * 1024),
        Int64(64 * 1024 * 1024) * 10000,
        Int64(64 * 1024 * 1024) * 10000 + 1,
        Int64(5) * 1024 * 1024 * 1024 * 1024,
        MAX_MULTIPART_BYTES,
    ]:
        var plan = plan_multipart(size, MIN_PART_BYTES)
        assert_true(plan.part_count <= 10000)
        assert_true(plan.part_size_bytes >= MIN_PART_BYTES)
        assert_true(plan.part_size_bytes <= MAX_PART_BYTES)
        if size == 0:
            assert_equal(plan.part_count, 0)
        else:
            assert_equal(plan.offset(1), Int64(0))
            assert_equal(
                plan.offset(plan.part_count) + plan.length(plan.part_count),
                size,
            )
            assert_true(plan.length(plan.part_count) > 0)
    var maximum = plan_multipart(MAX_MULTIPART_BYTES)
    assert_equal(maximum.part_count, 10000)
    assert_equal(maximum.part_size_bytes, MAX_PART_BYTES)
    for size in [
        Int64(-1),
        MAX_MULTIPART_BYTES + 1,
        Int64(9223372036854775807),
    ]:
        var failed = False
        try:
            _ = plan_multipart(size)
        except:
            failed = True
        assert_true(failed)
    for target in [Int64(0), MIN_PART_BYTES - 1, MAX_PART_BYTES + 1]:
        var failed = False
        try:
            _ = plan_multipart(1, target)
        except:
            failed = True
        assert_true(failed)
    print(
        "64-bit multipart planning through 10000 x 5 GiB, overflow and boundary controls passed without payload allocation"
    )
