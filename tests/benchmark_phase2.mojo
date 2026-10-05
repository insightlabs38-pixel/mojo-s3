"""One measured operation per process; orchestrator records RSS and wall time."""
from std.os import getenv
from mojo_s3 import S3Store, S3Config, PutOptions
from mojo_s3.files import NativeFile, digest_file
from mojo_s3.downloads import concurrent_download_file
from mojo_s3.transfer_control import TransferControl, NoProgress
from mojo_s3.multipart import multipart_upload_file
from mojo_s3.concurrent import concurrent_multipart_upload_file


def main() raises:
    var store = S3Store(S3Config.from_env())
    var bucket = getenv("S3_TEST_BUCKET")
    var mode = getenv("S3_BENCH_MODE")
    var source = getenv("S3_STREAM_SOURCE")
    var destination = getenv("S3_STREAM_DESTINATION")
    if mode == "stream":
        _ = store.download_file(bucket, "benchmark", destination)
    elif mode == "download":
        var control = TransferControl()
        var observer = NoProgress()
        _ = concurrent_download_file(
            store,
            bucket,
            "benchmark",
            destination,
            Int(getenv("S3_BENCH_WORKERS")),
            5 * 1024 * 1024,
            control,
            observer,
        )
    elif mode == "multipart":
        _ = multipart_upload_file(
            store, bucket, "upload", source, 5 * 1024 * 1024
        )
        store.delete(bucket, "upload")
    elif mode == "upload":
        _ = concurrent_multipart_upload_file(
            store,
            bucket,
            "upload",
            source,
            Int(getenv("S3_BENCH_WORKERS")),
            5 * 1024 * 1024,
        )
        store.delete(bucket, "upload")
    else:
        var file = NativeFile(source)
        _ = digest_file(file, mode)
