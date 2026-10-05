from std.testing import assert_equal, assert_true
from mojo_s3 import S3Store, S3Config, VersionsPaginator, list_object_versions


def main() raises:
    var store = S3Store(S3Config.from_env())
    var page = list_object_versions(
        store, "bucket", "prefix/", "/", "prefix/雪 +", "opaque%2F+/=", 2
    )
    assert_equal(page.versions[0].version_id, "opaque%2F+/=")
    assert_equal(page.delete_markers[0].version_id, "null")
    var listed = store.list("list-v2")
    assert_equal(listed.objects[0].key, "prefix/a b+c%2B")
    assert_equal(listed.prefixes[0], "prefix/a b+/")
    var cycle = VersionsPaginator("cycle", page_size=1, max_pages=5)
    _ = cycle.next_page(store)
    _ = cycle.next_page(store)
    var failed = False
    try:
        _ = cycle.next_page(store)
    except:
        failed = True
    assert_true(failed)
    assert_equal(cycle.pages_loaded, 2)
    assert_equal(cycle.key_marker, "b")
    var limited = VersionsPaginator("limited", page_size=1, max_pages=1)
    _ = limited.next_page(store)
    failed = False
    try:
        _ = limited.next_page(store)
    except:
        failed = True
    assert_true(failed)
    assert_equal(limited.pages_loaded, 1)
    print(
        "Signed version queries preserve opaque IDs; cyclic markers and page exhaustion fail atomically"
    )
