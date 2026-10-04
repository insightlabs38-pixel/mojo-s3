"""Environment-driven range, presign, streaming, and multipart example."""
from std.os import getenv
from mojo_s3.client import S3Store
from mojo_s3.config import S3Config
from mojo_s3.crypto import random_token
from mojo_s3.objects import ObjectRange
from mojo_s3.multipart import multipart_upload_file
from mojo_s3.concurrent import concurrent_multipart_upload_file


def main() raises:
    var store = S3Store(S3Config.from_env())
    var bucket = getenv("S3_TEST_BUCKET")
    var source = getenv("S3_STREAM_SOURCE")
    var destination = getenv("S3_STREAM_DESTINATION")
    var key = "example-" + random_token()
    if not bucket or not source or not destination:
        raise Error(
            "Set S3_TEST_BUCKET, S3_STREAM_SOURCE, S3_STREAM_DESTINATION"
        )
    try:
        _ = store.upload_file(bucket, key, source)
        _ = store.download_file(bucket, key, destination)
        if store.head(bucket, key).size:
            var first = store.get_range(bucket, key, ObjectRange(0, 0))
            print("First byte:", first.data[0])
        # This URL is a bearer credential: return it only to authorized callers.
        var url = store.presign("GET", bucket, key, 60)
        print("Presigned URL generated; length:", url.byte_length())
        _ = multipart_upload_file(store, bucket, key, source)
        _ = concurrent_multipart_upload_file(store, bucket, key, source, 4)
    except e:
        store.delete(bucket, key)
        raise e^
    store.delete(bucket, key)
