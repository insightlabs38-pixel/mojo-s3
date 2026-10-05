from std.os import getenv
from std.collections import List
from std.testing import assert_equal, assert_true
from mojo_s3 import S3Store, S3Config, ReadOptions, Conditions, ObjectIdentifier


def main() raises:
    var store = S3Store(S3Config.from_env())
    var failed = False
    try:
        _ = store.copy_object("bucket", "source", "bucket", "copy-error")
    except:
        failed = True
    assert_true(failed)
    assert_equal(store.last_error.value().code, "SlowDown")
    failed = False
    try:
        _ = store.copy_object("bucket", "source", "bucket", "copy-malformed")
    except:
        failed = True
    assert_true(failed)
    var objects: List[ObjectIdentifier] = [
        ObjectIdentifier("good", ""),
        ObjectIdentifier("denied", ""),
    ]
    var result = store.delete_objects("bucket", objects)
    assert_true(not result.all_succeeded())
    assert_equal(len(result.deleted), 1)
    assert_equal(result.errors[0].code, "AccessDenied")
    for name in ["omitted", "duplicate", "unrequested"]:
        objects = [ObjectIdentifier(name, "")]
        if name == "duplicate":
            objects.append(ObjectIdentifier("second", ""))
        failed = False
        try:
            _ = store.delete_objects("bucket", objects)
        except:
            failed = True
        assert_true(failed)
    failed = False
    try:
        _ = store.get(
            "bucket",
            "cached",
            ReadOptions(conditions=Conditions(if_none_match='"tag"')),
        )
    except:
        failed = True
    assert_true(failed)
    assert_equal(store.last_error.value().category, "NotModified")
    print(
        "Copy embedded/malformed errors, batch partial/omitted outcomes and 304 passed"
    )
