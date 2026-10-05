from std.testing import assert_equal, assert_true
from mojo_s3.download_plan import plan_download
from mojo_s3.multipart_plan import MAX_MULTIPART_BYTES


def main() raises:
    for size in [
        Int64(0),
        Int64(1),
        Int64(4096),
        Int64(4097),
        MAX_MULTIPART_BYTES,
    ]:
        for workers in [1, 2, 4, 8, 16]:
            var plan = plan_download(size, 4096, workers, 64 * 1024 * 1024)
            assert_true(plan.range_count <= 1000000)
            assert_true(plan.range_size_bytes <= 64 * 1024 * 1024)
            assert_true(
                Int64(plan.workers) * plan.range_size_bytes <= 64 * 1024 * 1024
            )
            if size:
                assert_true(plan.workers > 0)
                assert_equal(
                    (size - 1) // plan.range_size_bytes + 1,
                    Int64(plan.range_count),
                )
            else:
                assert_equal(plan.workers, 0)
                assert_equal(plan.range_count, 0)
    var reduced = plan_download(100000, 4096, 16, 8192)
    assert_equal(reduced.workers, 2)
    for size in [
        Int64(-1),
        MAX_MULTIPART_BYTES + 1,
        Int64(9223372036854775807),
    ]:
        var failed = False
        try:
            _ = plan_download(size, 4096, 4, 65536)
        except:
            failed = True
        assert_true(failed)
    var failed = False
    try:
        _ = plan_download(MAX_MULTIPART_BYTES, 4096, 16, 65536)
    except:
        failed = True
    assert_true(failed)
    print(
        "64-bit download scheduling, bounded worker buffers and outcome counts passed"
    )
