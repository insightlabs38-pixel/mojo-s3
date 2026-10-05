from std.testing import assert_equal, assert_true
from mojo_s3 import (
    TransferManager,
    TransferOptions,
    S3Store,
    S3Config,
    list_parts,
    list_multipart_uploads,
    multipart_copy_object,
    get_object_tagging,
    CopyOptions,
)


def main() raises:
    var store = S3Store(S3Config.from_env())
    store.config.max_attempts = 1
    for mode in [
        "identity",
        "duplicate",
        "oversized",
        "marker",
        "negative",
        "part-size",
        "overflow",
        "boolean",
    ]:
        var failed = False
        try:
            _ = list_parts(store, "bucket", mode, "opaque+/id=", 0, 1)
        except:
            failed = True
        assert_true(failed)
    for mode in ["outside", "duplicate", "oversized", "marker"]:
        var failed = False
        try:
            _ = list_multipart_uploads(
                store, mode, "prefix/", "prefix/a", "old", 1
            )
        except:
            failed = True
        assert_true(failed)
    for mode in ["duplicate", "missing", "oversized"]:
        var failed = False
        try:
            _ = get_object_tagging(store, "bucket", mode)
        except:
            failed = True
        assert_true(failed)
    for mode in ["part-error", "complete-error", "abort-error"]:
        var failed = False
        try:
            _ = multipart_copy_object(store, "bucket", "source", "bucket", mode)
        except:
            failed = True
        assert_true(failed)
        assert_equal(store.last_error.value().code, "SlowDown")
    var manager = TransferManager(
        S3Store(S3Config.from_env()),
        TransferOptions(part_size=5 * 1024 * 1024 * 1024),
    )
    var wide = manager.copy_object(
        "bucket", "wide-source", "bucket", "wide-copy"
    )
    assert_equal(wide.etag, "wide-result")
    var invalid = CopyOptions(tagging_directive="invalid")
    var failed = False
    try:
        _ = multipart_copy_object(
            store, "bucket", "source", "bucket", "invalid", invalid
        )
    except:
        failed = True
    assert_true(failed)
    print(
        "Multipart inspection/tag validation, embedded copy errors and abort-primary preservation passed"
    )
