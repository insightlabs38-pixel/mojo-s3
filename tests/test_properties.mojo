"""Deterministic property coverage for URI and restricted XML response parsing."""
from std.collections import List
from std.testing import assert_equal, assert_true
from mojo_s3.client import decode_key
from mojo_s3.protocol import uri_encode, Field, canonical_query, normalize_space
from mojo_s3.multipart import escape_xml
from mojo_s3.xml import parse_xml, child_text


def main() raises:
    var symbols: List[String] = [
        "a",
        "Z",
        "0",
        " ",
        "/",
        "%",
        "+",
        "?",
        "#",
        "&",
        "=",
        "é",
        "雪",
        "🔥",
        "~",
        "-",
        "_",
        ".",
        "\n",
        "\t",
    ]
    var state = UInt32(74391)
    for trial in range(2000):
        var value = String()
        for _ in range(1 + trial % 37):
            state = state * UInt32(1664525) + UInt32(1013904223)
            value += symbols[Int(state % UInt32(len(symbols)))]
        assert_equal(decode_key(uri_encode(value)), value)
        assert_equal(decode_key(uri_encode(value, True)), value)
        var query: List[Field] = [
            Field(value, " "),
            Field("%", value),
            Field(value, "+"),
        ]
        var reverse: List[Field] = [
            query[2].copy(),
            query[1].copy(),
            query[0].copy(),
        ]
        assert_equal(canonical_query(query), canonical_query(reverse))
        var nodes = parse_xml(
            "<r><Key>"
            + escape_xml(value)
            + "</Key><Nested><Key>decoy</Key></Nested></r>"
        )
        assert_equal(child_text(nodes, 0, "Key"), value)
    assert_equal(decode_key(uri_encode("\x00")), "\x00")
    var text = "  é\t 雪   🔥  "
    assert_equal(normalize_space(normalize_space(text)), normalize_space(text))
    for bad in ["%", "%0", "%GG", "%00%FF", "%C0%AF", "%ED%A0%80"]:
        var failed = False
        try:
            _ = decode_key(bad)
        except:
            failed = True
        assert_true(failed)
    var deep = String()
    for _ in range(66):
        deep += "<n>"
    for _ in range(66):
        deep += "</n>"
    var failed = False
    try:
        _ = parse_xml(deep)
    except:
        failed = True
    assert_true(failed)
    var duplicate = parse_xml("<r><Key>a</Key><Key>b</Key></r>")
    failed = False
    try:
        _ = child_text(duplicate, 0, "Key")
    except:
        failed = True
    assert_true(failed)
    print(
        "2000 URI/query/XML properties; invalid percent/UTF8, nesting limits, and duplicate-element rejection passed"
    )
