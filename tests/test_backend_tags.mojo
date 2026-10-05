"""Optional backend classifier: failures are emitted, never hidden as passes."""
from std.os import getenv
from std.testing import assert_equal
from mojo_s3 import S3Store, S3Config, PutOptions, Field
from mojo_s3.crypto import bytes_of, random_token
from mojo_s3.multipart import initiate, upload_part, complete, abort
from mojo_s3.tagging import get_object_tagging


def main() raises:
    var store = S3Store(S3Config.from_env())
    store.config.max_attempts = 1
    var bucket = getenv("S3_TEST_BUCKET")
    for value in ["native", "a b", "a+b", "a/b", "a_b", "a-b", "雪"]:
        var key = "mojo-backend-tags/" + random_token()
        var upload_id = ""
        try:
            var options = PutOptions()
            options.tags = [Field("fixture", value)]
            upload_id = initiate(store, bucket, key, options)
            var part = upload_part(
                store, bucket, key, upload_id, 1, bytes_of("content")
            )
            _ = complete(store, bucket, key, upload_id, [part^])
            upload_id = ""
            var tags = get_object_tagging(store, bucket, key)
            assert_equal(len(tags), 1)
            assert_equal(tags[0].value, value)
            print("NATIVE-TAG", value, "PASS")
        except error:
            print("NATIVE-TAG", value, "FAIL", String(error))
        finally:
            if upload_id:
                abort(store, bucket, key, upload_id)
            store.delete(bucket, key)
