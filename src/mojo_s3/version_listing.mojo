"""Experimental, bounded version listing; never mutates bucket/object state."""
from std.collections import List
from mojo_s3.client import S3Store, decimal, decode_key
from mojo_s3.protocol import Field
from mojo_s3.xml import parse_xml, child_text
from mojo_s3.crypto import bytes_of, sha256_hex


def marker_fingerprint(key: String, version_id: String) raises -> String:
    # Length framing keeps opaque identifiers unambiguous; retain fixed-size
    # fingerprints rather than a history of possibly large backend strings.
    return sha256_hex(
        bytes_of(String(key.byte_length()) + ":" + key + version_id)
    )


@fieldwise_init
struct ObjectVersion(Copyable, Movable):
    var key: String
    var version_id: String
    var is_latest: Bool
    var etag: String
    var size_bytes: Int64
    var last_modified: String
    var storage_class: String


@fieldwise_init
struct DeleteMarker(Copyable, Movable):
    var key: String
    var version_id: String
    var is_latest: Bool
    var last_modified: String


@fieldwise_init
struct VersionsPage(Copyable, Movable):
    var versions: List[ObjectVersion]
    var delete_markers: List[DeleteMarker]
    var prefixes: List[String]
    var truncated: Bool
    var next_key_marker: String
    var next_version_id_marker: String


def version_flag(text: String) raises -> Bool:
    if text != "true" and text != "false":
        raise Error("Missing or invalid version listing boolean")
    return text == "true"


def version_key(text: String, encoded: Bool) raises -> String:
    if not encoded:
        return text
    # Match the independent S3 reference client's unquote_plus semantics:
    # '+' or '%20' is a space, '%2B' is a literal plus. IDs never enter here.
    return decode_key(text)


def parse_versions_page(
    text: String,
    bucket: String,
    prefix: String = "",
    key_marker: String = "",
    version_id_marker: String = "",
    max_keys: Int = 1000,
) raises -> VersionsPage:
    var nodes = parse_xml(text)
    if (
        nodes[0].name != "ListVersionsResult"
        or child_text(nodes, 0, "Name") != bucket
    ):
        raise Error("Unexpected ListObjectVersions result or bucket")
    var encoding = child_text(nodes, 0, "EncodingType")
    if encoding and encoding != "url":
        raise Error("Unexpected version listing encoding")
    var encoded = encoding == "url"
    var versions = List[ObjectVersion]()
    var markers = List[DeleteMarker]()
    var prefixes = List[String]()
    var identities = List[Field]()
    var count = 0
    for i in range(len(nodes)):
        if nodes[i].parent != 0:
            continue
        var kind = nodes[i].name
        if kind == "Version" or kind == "DeleteMarker":
            var key = version_key(child_text(nodes, i, "Key"), encoded)
            var version_id = child_text(nodes, i, "VersionId")
            var modified = child_text(nodes, i, "LastModified")
            if (
                not key
                or not version_id
                or not modified
                or not key.startswith(prefix)
            ):
                raise Error("Invalid version listing identity")
            if key == key_marker and version_id == version_id_marker:
                raise Error("Version listing repeated requested marker")
            for identity in identities:
                if identity.name == key and identity.value == version_id:
                    raise Error("Duplicate version listing identity")
            identities.append(Field(key, version_id))
            var latest = version_flag(child_text(nodes, i, "IsLatest"))
            if kind == "Version":
                var etag = child_text(nodes, i, "ETag")
                if not etag:
                    raise Error("Missing object version ETag")
                versions.append(
                    ObjectVersion(
                        key,
                        version_id,
                        latest,
                        etag,
                        Int64(decimal(child_text(nodes, i, "Size"))),
                        modified,
                        child_text(nodes, i, "StorageClass"),
                    )
                )
            else:
                markers.append(DeleteMarker(key, version_id, latest, modified))
            count += 1
        elif kind == "CommonPrefixes":
            var value = version_key(child_text(nodes, i, "Prefix"), encoded)
            if not value or not value.startswith(prefix):
                raise Error("Invalid version listing common prefix")
            for existing in prefixes:
                if existing == value:
                    raise Error("Duplicate version listing common prefix")
            prefixes.append(value)
            count += 1
        if count > max_keys:
            raise Error("Version listing exceeded requested page bound")
    var truncated = version_flag(child_text(nodes, 0, "IsTruncated"))
    var next_key = version_key(child_text(nodes, 0, "NextKeyMarker"), encoded)
    # Version IDs are opaque, including percent signs, '+', '/' and literal 'null'.
    var next_id = child_text(nodes, 0, "NextVersionIdMarker")
    if truncated and (
        not next_key
        or not next_key.startswith(prefix)
        or (next_key == key_marker and next_id == version_id_marker)
    ):
        raise Error("Version listing markers failed to advance")
    return VersionsPage(
        versions^, markers^, prefixes^, truncated, next_key, next_id
    )


def list_object_versions(
    mut store: S3Store,
    bucket: String,
    prefix: String = "",
    delimiter: String = "",
    key_marker: String = "",
    version_id_marker: String = "",
    max_keys: Int = 1000,
) raises -> VersionsPage:
    if (
        max_keys < 1
        or max_keys > 1000
        or (version_id_marker and not key_marker)
    ):
        raise Error("Invalid ListObjectVersions bounds or markers")
    var query: List[Field] = [
        Field("versions", ""),
        Field("encoding-type", "url"),
        Field("max-keys", String(max_keys)),
    ]
    for field in [
        Field("prefix", prefix),
        Field("delimiter", delimiter),
        Field("key-marker", key_marker),
        Field("version-id-marker", version_id_marker),
    ]:
        if field.value:
            query.append(field.copy())
    var response = store.request(
        "GET", bucket, "", query, List[Field](), List[UInt8]()
    )
    return parse_versions_page(
        String(
            from_utf8=Span(
                unsafe_ptr=response.body.unsafe_ptr(), length=len(response.body)
            )
        ),
        bucket,
        prefix,
        key_marker,
        version_id_marker,
        max_keys,
    )


struct VersionsPaginator(Movable):
    var bucket: String
    var prefix: String
    var delimiter: String
    var key_marker: String
    var version_id_marker: String
    var page_size: Int
    var max_pages: Int
    var pages_loaded: Int
    var done: Bool
    var _seen_markers: List[String]

    def __init__(
        out self,
        bucket: String,
        prefix: String = "",
        delimiter: String = "",
        page_size: Int = 1000,
        max_pages: Int = 10000,
        key_marker: String = "",
        version_id_marker: String = "",
    ) raises:
        if (
            page_size < 1
            or page_size > 1000
            or max_pages < 1
            or max_pages > 1000000
            or (version_id_marker and not key_marker)
        ):
            raise Error("Invalid versions paginator bounds or markers")
        self.bucket = bucket
        self.prefix = prefix
        self.delimiter = delimiter
        self.key_marker = key_marker
        self.version_id_marker = version_id_marker
        self.page_size = page_size
        self.max_pages = max_pages
        self.pages_loaded = 0
        self.done = False
        self._seen_markers = [marker_fingerprint(key_marker, version_id_marker)]

    def next_page(mut self, mut store: S3Store) raises -> VersionsPage:
        if self.done or self.pages_loaded >= self.max_pages:
            raise Error("Version pagination complete or page bound exceeded")
        var page = list_object_versions(
            store,
            self.bucket,
            self.prefix,
            self.delimiter,
            self.key_marker,
            self.version_id_marker,
            self.page_size,
        )
        if page.truncated:
            var fingerprint = marker_fingerprint(
                page.next_key_marker, page.next_version_id_marker
            )
            for marker in self._seen_markers:
                if marker == fingerprint:
                    raise Error("Version pagination marker cycle")
            self._seen_markers.append(fingerprint^)
        self.key_marker = page.next_key_marker
        self.version_id_marker = page.next_version_id_marker
        self.done = not page.truncated
        self.pages_loaded += 1
        return page^
