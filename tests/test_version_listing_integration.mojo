"""Only uses an explicitly supplied, already-versioned isolated fixture bucket."""
from std.collections import List
from std.os import getenv
from std.testing import assert_equal, assert_true
from mojo_s3 import (
    S3Store,
    S3Config,
    ReadOptions,
    VersionsPaginator,
    list_object_versions,
)
from mojo_s3.crypto import bytes_of, random_token


def main() raises:
    var bucket = getenv("S3_VERSIONED_TEST_BUCKET")
    if not bucket:
        raise Error("Supply an authorized preconfigured versioned bucket")
    var store = S3Store(S3Config.from_env())
    var prefix = "mojo-version-list/" + random_token() + "/"
    var key = prefix + "雪 + /%?"
    var grouped = prefix + "sub/child"
    var first = store.put(bucket, key, bytes_of("first"))
    var second = store.put(bucket, key, bytes_of("second"))
    var child = store.put(bucket, grouped, bytes_of("child"))
    var delete_id = ""
    try:
        var response = store.request(
            "DELETE", bucket, key, List[Field](), List[Field](), List[UInt8]()
        )
        delete_id = get_header(response.headers, "x-amz-version-id")
        assert_true(delete_id != "")
        var paginator = VersionsPaginator(
            bucket, prefix=prefix, page_size=1, max_pages=8
        )
        var version_ids = List[String]()
        var markers = 0
        while not paginator.done:
            var page = paginator.next_page(store)
            assert_true(len(page.versions) + len(page.delete_markers) <= 1)
            for version in page.versions:
                assert_true(version.key == key or version.key == grouped)
                version_ids.append(version.version_id)
            for marker in page.delete_markers:
                assert_equal(marker.key, key)
                assert_equal(marker.version_id, delete_id)
                assert_true(marker.is_latest)
                markers += 1
        assert_equal(len(version_ids), 3)
        assert_equal(markers, 1)
        for identity in [first.version_id, second.version_id, child.version_id]:
            var found = False
            for listed in version_ids:
                found = found or listed == identity
            assert_true(found)
        var delimited = list_object_versions(
            store, bucket, prefix=prefix, delimiter="/"
        )
        assert_equal(len(delimited.prefixes), 2)
        assert_equal(len(delimited.versions), 0)
        # An explicit opaque marker resumes the key's remaining older version.
        var resumed = list_object_versions(
            store,
            bucket,
            prefix=key,
            key_marker=key,
            version_id_marker=second.version_id,
        )
        assert_equal(len(resumed.versions), 1)
        assert_equal(resumed.versions[0].version_id, first.version_id)
    finally:
        store.delete(bucket, key, ReadOptions(first.version_id))
        store.delete(bucket, key, ReadOptions(second.version_id))
        store.delete(bucket, grouped, ReadOptions(child.version_id))
        if delete_id:
            store.delete(bucket, key, ReadOptions(delete_id))
    assert_equal(
        len(list_object_versions(store, bucket, prefix=prefix).versions), 0
    )
    print(
        "Version/delete-marker pagination, opaque resume, delimiter and known-ID cleanup passed"
    )


from mojo_s3.protocol import Field, get_header
