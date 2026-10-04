from std.collections import List
from std.os import getenv
from std.testing import assert_equal, assert_true
from mojo_s3.client import S3Store
from mojo_s3.config import S3Config
from mojo_s3.crypto import random_token, bytes_of, sha256_hex
from mojo_s3.objects import ListOptions


def main() raises:
    var store = S3Store(S3Config.from_env())
    var bucket = getenv("S3_TEST_BUCKET")
    var prefix = "mojo-extended-" + random_token() + "/"
    var keys: List[String] = [
        "dir/file",
        "dir//file",
        "a/./b",
        "a/../b",
        "/leading",
        "trailing/",
        "control\nkey",
    ]
    try:
        for key in keys:
            _ = store.put(bucket, prefix + key, bytes_of("distinct-" + key))
        for key in keys:
            var result = store.get(bucket, prefix + key)
            assert_equal(
                sha256_hex(result.data), sha256_hex(bytes_of("distinct-" + key))
            )
            assert_equal(
                store.head(bucket, prefix + key).size, result.metadata.size
            )
        var page = store.list(bucket, ListOptions(prefix))
        assert_equal(len(page.objects), len(keys))
        for key in keys:
            var found = False
            for object in page.objects:
                if object.key == prefix + key:
                    found = True
            assert_true(found)
    except e:
        for key in keys:
            try:
                store.delete(bucket, prefix + key)
            except:
                pass
        raise e^
    for key in keys:
        store.delete(bucket, prefix + key)
        assert_true(not store.exists(bucket, prefix + key))
    print(
        "repeated slash, dot paths, empty components, trailing slash, newline keys remain distinct through CRUD and LIST"
    )
