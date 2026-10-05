"""Version-aware object tags, separate from bucket administration."""
from std.collections import List
from mojo_s3.client import S3Store
from mojo_s3.objects import ReadOptions
from mojo_s3.protocol import Field
from mojo_s3.options import xml_text
from mojo_s3.crypto import bytes_of, content_md5
from mojo_s3.xml import parse_xml, child_text


def tag_manifest(tags: List[Field]) raises -> String:
    if len(tags) > 10:
        raise Error("S3 objects support at most 10 tags")
    var seen = List[String]()
    var text = "<Tagging><TagSet>"
    for tag in tags:
        if not tag.name:
            raise Error("Object tag keys must be nonempty")
        for key in seen:
            if key == tag.name:
                raise Error("Duplicate object tag key")
        seen.append(tag.name)
        text += (
            "<Tag><Key>"
            + xml_text(tag.name)
            + "</Key><Value>"
            + xml_text(tag.value)
            + "</Value></Tag>"
        )
    return text + "</TagSet></Tagging>"


def get_object_tagging(
    mut store: S3Store, bucket: String, key: String, version_id: String = ""
) raises -> List[Field]:
    var query = ReadOptions(version_id).query()
    query.append(Field("tagging", ""))
    var response = store.request(
        "GET", bucket, key, query, List[Field](), List[UInt8]()
    )
    var nodes = parse_xml(
        String(
            from_utf8=Span(
                unsafe_ptr=response.body.unsafe_ptr(), length=len(response.body)
            )
        )
    )
    if nodes[0].name != "Tagging":
        raise Error("Unexpected object tagging response")
    var tag_set = -1
    for i in range(len(nodes)):
        if nodes[i].parent == 0 and nodes[i].name == "TagSet":
            if tag_set >= 0:
                raise Error("Duplicate TagSet")
            tag_set = i
    if tag_set < 0:
        raise Error("Missing TagSet")
    var tags = List[Field]()
    for i in range(len(nodes)):
        if nodes[i].parent == tag_set and nodes[i].name == "Tag":
            tags.append(
                Field(
                    child_text(nodes, i, "Key"), child_text(nodes, i, "Value")
                )
            )
    _ = tag_manifest(tags)  # Apply the same count/uniqueness/XML validation.
    return tags^


def put_object_tagging(
    mut store: S3Store,
    bucket: String,
    key: String,
    tags: List[Field],
    version_id: String = "",
) raises:
    var query = ReadOptions(version_id).query()
    query.append(Field("tagging", ""))
    var body = bytes_of(tag_manifest(tags))
    var headers: List[Field] = [
        Field("content-type", "application/xml"),
        Field("content-md5", content_md5(body)),
    ]
    _ = store.request("PUT", bucket, key, query, headers, body)


def delete_object_tagging(
    mut store: S3Store, bucket: String, key: String, version_id: String = ""
) raises:
    var query = ReadOptions(version_id).query()
    query.append(Field("tagging", ""))
    _ = store.request(
        "DELETE", bucket, key, query, List[Field](), List[UInt8]()
    )
