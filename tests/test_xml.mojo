from std.testing import assert_equal, assert_true
from mojo_s3.xml import parse_xml, child_text


def main() raises:
    var nodes = parse_xml(
        "<s:ListBucketResult xmlns:s='urn:s3'><s:Contents><s:Key>a&amp;b&#xE9;<![CDATA[<x>]]></s:Key><s:Size>3</s:Size></s:Contents><s:CommonPrefixes><s:Prefix>dir/</s:Prefix></s:CommonPrefixes></s:ListBucketResult>"
    )
    assert_equal(child_text(nodes, 1, "Key"), "a&bé<x>")
    assert_equal(child_text(nodes, 1, "Size"), "3")
    var failed = False
    try:
        _ = parse_xml("<!DOCTYPE x [<!ENTITY e 'bad'>]><x>&e;</x>")
    except:
        failed = True
    assert_true(failed)
    failed = False
    try:
        _ = parse_xml("<a><b></a>")
    except:
        failed = True
    assert_true(failed)
    print("XML entities, namespaces, CDATA, and malformed input tests passed")
