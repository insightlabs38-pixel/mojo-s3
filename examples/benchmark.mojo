"""Local repeatable S3 latency and transfer measurements; no marketing claims."""
from std.os import getenv
from std.time import perf_counter_ns
from mojo_s3.client import S3Store
from mojo_s3.config import S3Config
from mojo_s3.crypto import bytes_of, random_token, sha256_hex
from mojo_s3.files import NativeFile, hash_file
from mojo_s3.multipart import multipart_upload_file
from mojo_s3.concurrent import concurrent_multipart_upload_file
from mojo_s3.objects import ObjectRange
from std.testing import assert_equal


def main() raises:
    var store = S3Store(S3Config.from_env())
    var bucket = getenv("S3_TEST_BUCKET")
    var source = getenv("S3_STREAM_SOURCE")
    var destination = getenv("S3_STREAM_DESTINATION")
    if not bucket or not source or not destination:
        raise Error(
            "Benchmark requires test bucket and source/destination files"
        )
    var key = "mojo-bench-" + random_token()
    var data = bytes_of("small useful object payload")
    try:
        for _ in range(10):
            _ = store.put(bucket, key, data)
            _ = store.get(bucket, key)
        var start = perf_counter_ns()
        for _ in range(100):
            _ = store.put(bucket, key, data)
        var put_ns = perf_counter_ns() - start
        start = perf_counter_ns()
        for _ in range(100):
            var result = store.get(bucket, key)
            assert_equal(sha256_hex(result.data), sha256_hex(data))
        var get_ns = perf_counter_ns() - start
        print("small_put_mean_us", Float64(put_ns) / 100000.0)
        print("small_get_mean_us", Float64(get_ns) / 100000.0)
        var original = NativeFile(source)
        var size = original.length()
        start = perf_counter_ns()
        _ = store.upload_file(bucket, key, source)
        var upload_ns = perf_counter_ns() - start
        start = perf_counter_ns()
        _ = store.download_file(bucket, key, destination)
        var download_ns = perf_counter_ns() - start
        var downloaded = NativeFile(destination)
        assert_equal(hash_file(original), hash_file(downloaded))
        print("source_bytes", size)
        print(
            "stream_upload_mib_s",
            Float64(size) * 1e9 / Float64(upload_ns) / 1048576.0,
        )
        print(
            "stream_download_mib_s",
            Float64(size) * 1e9 / Float64(download_ns) / 1048576.0,
        )
        if size > 1024 * 1024:
            start = perf_counter_ns()
            var range = store.get_range(
                bucket, key, ObjectRange(0, 1024 * 1024 - 1)
            )
            var range_ns = perf_counter_ns() - start
            print("range_mib_s", 1e9 / Float64(range_ns))
        start = perf_counter_ns()
        _ = multipart_upload_file(store, bucket, key, source)
        var multipart_ns = perf_counter_ns() - start
        start = perf_counter_ns()
        _ = concurrent_multipart_upload_file(store, bucket, key, source, 4)
        var concurrent_ns = perf_counter_ns() - start
        _ = store.download_file(bucket, key, destination)
        var final_file = NativeFile(destination)
        assert_equal(hash_file(original), hash_file(final_file))
        print(
            "sequential_multipart_mib_s",
            Float64(size) * 1e9 / Float64(multipart_ns) / 1048576.0,
        )
        print(
            "four_worker_multipart_mib_s",
            Float64(size) * 1e9 / Float64(concurrent_ns) / 1048576.0,
        )
    except e:
        store.delete(bucket, key)
        raise e^
    store.delete(bucket, key)
