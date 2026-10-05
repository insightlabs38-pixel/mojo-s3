from std.testing import assert_equal, assert_true
from mojo_s3.version_listing import parse_versions_page, VersionsPaginator


def document(entries: String, tail: String = "") -> String:
    return (
        "<ListVersionsResult><Name>bucket</Name><EncodingType>url</EncodingType><IsTruncated>false</IsTruncated>"
        + entries
        + tail
        + "</ListVersionsResult>"
    )


def version(
    key: String = "prefix%2F%E9%9B%AA%20%2B",
    identity: String = "opaque+/%25=",
    size: String = "9223372036854775807",
) -> String:
    return (
        "<Version><Key>"
        + key
        + "</Key><VersionId>"
        + identity
        + "</VersionId><IsLatest>false</IsLatest><LastModified>date</LastModified><ETag>opaque</ETag><Size>"
        + size
        + "</Size></Version>"
    )


def reject(text: String, max_keys: Int = 1000) raises:
    var failed = False
    try:
        _ = parse_versions_page(text, "bucket", "prefix/", max_keys=max_keys)
    except:
        failed = True
    assert_true(failed)


def main() raises:
    var marker = "<DeleteMarker><Key>prefix%2Fa</Key><VersionId>null</VersionId><IsLatest>true</IsLatest><LastModified>date</LastModified></DeleteMarker>"
    var prefix = (
        "<CommonPrefixes><Prefix>prefix%2Fsub%2F</Prefix></CommonPrefixes>"
    )
    var page = parse_versions_page(
        document(version() + marker + prefix), "bucket", "prefix/", max_keys=3
    )
    assert_equal(page.versions[0].key, "prefix/雪 +")
    assert_equal(page.versions[0].version_id, "opaque+/%25=")
    assert_equal(page.versions[0].size_bytes, Int64(9223372036854775807))
    assert_equal(page.delete_markers[0].version_id, "null")
    assert_true(page.delete_markers[0].is_latest)
    assert_equal(page.prefixes[0], "prefix/sub/")
    assert_true(not page.truncated)
    var form_page = parse_versions_page(
        document(version(key="prefix%2F%E9%9B%AA+%2B")), "bucket", "prefix/"
    )
    assert_equal(form_page.versions[0].key, "prefix/雪 +")
    # Neither lexical version ordering nor timestamp ordering is inferred.
    var unordered = parse_versions_page(
        document(version(identity="z") + version(identity="a", size="0")),
        "bucket",
        "prefix/",
    )
    assert_equal(unordered.versions[1].version_id, "a")
    for bad in [
        document(version() + version()),
        document(version(size="-1")),
        document(version(size="9223372036854775808")),
        document(version(identity="")),
        document(version(key="outside")),
        document(version(key="prefix%GG")),
        document(version()).replace("<IsLatest>false", "<IsLatest>yes"),
        document(version()).replace("<ETag>opaque</ETag>", ""),
        document(version()).replace("<Name>bucket", "<Name>wrong"),
        document(version()).replace("<IsTruncated>false</IsTruncated>", ""),
        document(version()).replace("<IsTruncated>false", "<IsTruncated>true"),
        document(prefix + prefix.copy()),
        document(version(), "<IsTruncated>false</IsTruncated>"),
    ]:
        reject(bad)
    reject(document(version() + marker), 1)
    var next_page = parse_versions_page(
        document(
            version(),
            "<NextKeyMarker>prefix%2F%E9%9B%AA</NextKeyMarker><NextVersionIdMarker>opaque%2F+</NextVersionIdMarker>",
        ).replace("<IsTruncated>false", "<IsTruncated>true"),
        "bucket",
        "prefix/",
    )
    assert_equal(next_page.next_key_marker, "prefix/雪")
    assert_equal(next_page.next_version_id_marker, "opaque%2F+")
    for bound in [0, 1001]:
        var failed = False
        try:
            _ = VersionsPaginator("bucket", page_size=bound)
        except:
            failed = True
        assert_true(failed)
    print(
        "Owned version/delete-marker pages, opaque IDs, URL keys and bounded malformed responses passed"
    )
