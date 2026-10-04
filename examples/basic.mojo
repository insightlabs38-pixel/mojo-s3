from std.os import getenv
from mojo_s3.config import S3Config
from mojo_s3.client import S3Store
from mojo_s3.crypto import bytes_of


def main() raises:
    var store = S3Store(S3Config.from_env())
    var bucket = getenv("S3_TEST_BUCKET", "mojo-test")
    _ = store.put(bucket, "hello.txt", bytes_of("hello from native Mojo"))
    var result = store.get(bucket, "hello.txt")
    print("Downloaded bytes:", len(result.data))
    print("ETag:", result.metadata.etag)
    var listing = store.list(bucket)
    print("Objects:", len(listing.objects))
    store.delete(bucket, "hello.txt")
