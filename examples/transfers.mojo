"""Stream a file or select bounded multipart; download atomically."""
from std.os import getenv
from mojo_s3 import S3Store, S3Config, TransferManager, TransferOptions


def main() raises:
    var bucket = getenv("S3_TEST_BUCKET")
    var source = getenv("S3_STREAM_SOURCE")
    var destination = getenv("S3_STREAM_DESTINATION")
    if not bucket or not source or not destination:
        raise Error("Set an isolated bucket, source file and destination file")
    var store = S3Store(S3Config.from_default())
    var manager = TransferManager(
        store^, TransferOptions(workers=4, part_size=8 * 1024 * 1024)
    )
    var key = "examples/transfer.bin"
    _ = manager.upload_file(bucket, key, source)
    _ = manager.download_file(bucket, key, destination)
    print("Transferred file; object remains at", key)
