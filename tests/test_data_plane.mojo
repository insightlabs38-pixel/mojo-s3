from std.collections import List
from std.testing import assert_equal, assert_true
from mojo_s3 import Conditions, ReadOptions, PutOptions, ObjectIdentifier
from mojo_s3.options import (
    copy_source,
    put_headers,
    delete_manifest,
    parse_delete_result,
    validate_delete_result,
    xml_text as mojo_xml_text,
)
from mojo_s3.protocol import get_header, canonical_query, Field
from mojo_s3.crypto import content_md5, bytes_of
from mojo_s3.config import aws_endpoint
from mojo_s3.errors import parse_s3_error
from mojo_s3.http import HttpResponse


def main() raises:
    assert_equal(
        copy_source("bucket", "a/%2F +é", "v/+="),
        "/bucket/a/%252F%20%2B%C3%A9?versionId=v%2F%2B%3D",
    )
    var read = ReadOptions("a/+", Conditions(if_match='"tag"'))
    assert_equal(canonical_query(read.query()), "versionId=a%2F%2B")
    assert_equal(get_header(read.headers(), "if-match"), '"tag"')
    var options = PutOptions("text/plain")
    options.encryption = "aws:kms"
    options.kms_key_id = "fixture-key"
    options.cache_control = "no-cache"
    options.tags.append(Field("a +", "b/"))
    var headers = put_headers(options)
    assert_equal(get_header(headers, "x-amz-tagging"), "a%20%2B=b%2F")
    assert_equal(get_header(headers, "x-amz-server-side-encryption"), "aws:kms")
    assert_equal(content_md5(bytes_of("abc")), "kAFQmDzST7DWlj99KOF/cg==")
    var objects: List[ObjectIdentifier] = [ObjectIdentifier("a<&", "v&")]
    assert_true("a&lt;&amp;" in delete_manifest(objects))
    var result = parse_delete_result(
        "<DeleteResult><Deleted><Key>a</Key></Deleted><Error><Key>b</Key><Code>AccessDenied</Code><Message>denied</Message></Error></DeleteResult>"
    )
    assert_true(not result.all_succeeded())
    assert_equal(result.deleted[0].key, "a")
    assert_equal(result.errors[0].code, "AccessDenied")
    for invalid in [
        "<DeleteResult><Deleted/></DeleteResult>",
        "<DeleteResult><Error><Key>a</Key></Error></DeleteResult>",
        "<Error><Code>denied</Code></Error>",
    ]:
        var failed = False
        try:
            _ = parse_delete_result(invalid)
        except:
            failed = True
        assert_true(failed)
    options.conditions = Conditions(if_none_match="*")
    var failed = False
    try:
        _ = put_headers(options, False)
    except:
        failed = True
    assert_true(failed)
    assert_equal(
        aws_endpoint("cn-north-1", True),
        "https://s3.dualstack.cn-north-1.amazonaws.com.cn",
    )
    assert_equal(
        aws_endpoint("us-east-1", True, True),
        "https://s3-fips.dualstack.us-east-1.amazonaws.com",
    )
    var redirected = parse_s3_error(
        HttpResponse(
            301, [Field("x-amz-bucket-region", "eu-west-1")], List[UInt8]()
        )
    )
    assert_equal(redirected.category, "RegionMismatch")
    assert_equal(redirected.bucket_region, "eu-west-1")
    # Seed 38: generate opaque query/copy/XML identities from reserved alphabets.
    var seed: UInt64 = 38
    var alphabet = "a/+?%=&<>"
    for i in range(64):
        seed = seed * UInt64(6364136223846793005) + 1
        var key = "generated/" + String(i)
        for _ in range(8):
            seed = seed * UInt64(6364136223846793005) + 1
            key += String(
                alphabet[
                    byte = Int(seed % UInt64(alphabet.byte_length())) : Int(
                        seed % UInt64(alphabet.byte_length())
                    )
                    + 1
                ]
            )
        var entries: List[ObjectIdentifier] = [
            ObjectIdentifier(key, "opaque/+=%" + String(i))
        ]
        var parsed = parse_delete_result(
            "<DeleteResult><Deleted><Key>"
            + mojo_xml_text(key)
            + "</Key><VersionId>opaque/+=%"
            + String(i)
            + "</VersionId></Deleted></DeleteResult>"
        )
        validate_delete_result(entries, parsed)
    print(
        "Typed conditions/options, copy encoding and batch partial outcomes passed"
    )
