"""S3-specific request construction; does not enlarge ObjectStore's trait."""
from std.collections import List
from mojo_s3.objects import (
    PutOptions,
    ObjectIdentifier,
    BatchDeleteResult,
    DeleteFailure,
    CopyOptions,
)
from mojo_s3.protocol import Field, canonical_query, uri_encode
from mojo_s3.xml import parse_xml, child_text


def put_headers(
    options: PutOptions, allow_conditions: Bool = True
) raises -> List[Field]:
    if options.encryption and options.encryption not in [
        "AES256",
        "aws:kms",
        "aws:kms:dsse",
    ]:
        raise Error("Unsupported server-side encryption mode")
    if options.kms_key_id and options.encryption not in [
        "aws:kms",
        "aws:kms:dsse",
    ]:
        raise Error("KMS key ID requires KMS encryption")
    if (
        options.conditions.if_modified_since
        or options.conditions.if_unmodified_since
    ):
        raise Error("PUT supports only If-Match and If-None-Match conditions")
    var conditions = options.conditions.headers()
    if not allow_conditions and len(conditions):
        raise Error("Conditional multipart/copy destination is not supported")
    if len(options.tags) > 10:
        raise Error("S3 object tags are limited to ten")
    for i in range(len(options.tags)):
        if not options.tags[i].name:
            raise Error("Object tag key must not be empty")
        for j in range(i):
            if options.tags[j].name == options.tags[i].name:
                raise Error("Duplicate object tag key")
    var result: List[Field] = [Field("content-type", options.content_type)]
    for field in [
        Field("content-disposition", options.content_disposition),
        Field("content-encoding", options.content_encoding),
        Field("cache-control", options.cache_control),
        Field("content-language", options.content_language),
        Field("x-amz-storage-class", options.storage_class),
        Field("x-amz-server-side-encryption", options.encryption),
        Field(
            "x-amz-server-side-encryption-aws-kms-key-id", options.kms_key_id
        ),
        Field("x-amz-expected-bucket-owner", options.expected_bucket_owner),
    ]:
        if field.value:
            result.append(field.copy())
    for field in options.metadata:
        result.append(Field("x-amz-meta-" + field.name.lower(), field.value))
    if len(options.tags):
        result.append(Field("x-amz-tagging", canonical_query(options.tags)))
    for field in conditions:
        result.append(field.copy())
    return result^


def copy_source(
    bucket: String, key: String, version_id: String = ""
) raises -> String:
    if not bucket or "/" in bucket or not key:
        raise Error("Copy requires a source bucket and key")
    var result = "/" + uri_encode(bucket) + "/" + uri_encode(key, True)
    if version_id:
        result += "?versionId=" + uri_encode(version_id)
    return result^


def xml_text(value: String) raises -> String:
    for b in value.as_bytes():
        if b < 32 and b != 9 and b != 10 and b != 13:
            raise Error("Object identifier cannot be represented in XML")
    return (
        value.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
        .replace("'", "&apos;")
        .replace("\r", "&#13;")
    )


def delete_manifest(objects: List[ObjectIdentifier]) raises -> String:
    if not len(objects) or len(objects) > 1000:
        raise Error("DeleteObjects requires 1..1000 identifiers")
    var result = "<Delete>"
    for i in range(len(objects)):
        var object = objects[i].copy()
        for j in range(i):
            if (
                object.key == objects[j].key
                and object.version_id == objects[j].version_id
            ):
                raise Error("Duplicate DeleteObjects identifier")
        if not object.key:
            raise Error("DeleteObjects key must not be empty")
        if object.key.byte_length() > 1024:
            raise Error("DeleteObjects key exceeds S3 byte limit")
        result += "<Object><Key>" + xml_text(object.key) + "</Key>"
        if object.version_id:
            result += (
                "<VersionId>" + xml_text(object.version_id) + "</VersionId>"
            )
        result += "</Object>"
    return result + "<Quiet>false</Quiet></Delete>"


def parse_delete_result(text: String) raises -> BatchDeleteResult:
    var nodes = parse_xml(text)
    if nodes[0].name != "DeleteResult":
        raise Error("Unexpected DeleteObjects XML root")
    var deleted = List[ObjectIdentifier]()
    var errors = List[DeleteFailure]()
    for i in range(len(nodes)):
        if nodes[i].parent != 0:
            continue
        var key = child_text(nodes, i, "Key")
        if nodes[i].name == "Deleted" or nodes[i].name == "Error":
            if not key:
                raise Error("DeleteObjects response has no key")
            var object = ObjectIdentifier(
                key, child_text(nodes, i, "VersionId")
            )
            if nodes[i].name == "Deleted":
                deleted.append(object^)
            else:
                var code = child_text(nodes, i, "Code")
                if not code:
                    raise Error("DeleteObjects failure has no code")
                errors.append(
                    DeleteFailure(
                        object^, code, child_text(nodes, i, "Message")
                    )
                )
    return BatchDeleteResult(deleted^, errors^)


def validate_delete_result(
    objects: List[ObjectIdentifier], result: BatchDeleteResult
) raises:
    if len(result.deleted) + len(result.errors) != len(objects):
        raise Error("DeleteObjects result omitted requested outcomes")
    var seen = List[Bool](length=len(objects), fill=False)
    for i in range(len(result.deleted) + len(result.errors)):
        var object = (
            result.deleted[i].copy() if i
            < len(result.deleted) else result.errors[
                i - len(result.deleted)
            ].object.copy()
        )
        var matched = False
        for j in range(len(objects)):
            if (
                object.key == objects[j].key
                and object.version_id == objects[j].version_id
            ):
                if seen[j]:
                    raise Error("Duplicate DeleteObjects response outcome")
                seen[j] = True
                matched = True
                break
        if not matched:
            raise Error(
                "DeleteObjects response contains an unrequested identifier"
            )
