from std.collections import List
from std.testing import assert_equal, assert_true
from mojo_s3.multipart import CompletedPart, completion_manifest


def main() raises:
    var parts: List[CompletedPart] = [
        CompletedPart(2, '"b"'),
        CompletedPart(1, '"a&"'),
    ]
    assert_equal(
        completion_manifest(parts),
        "<CompleteMultipartUpload><Part><PartNumber>1</PartNumber><ETag>&quot;a&amp;&quot;</ETag></Part><Part><PartNumber>2</PartNumber><ETag>&quot;b&quot;</ETag></Part></CompleteMultipartUpload>",
    )
    parts.append(CompletedPart(1, "duplicate"))
    var failed = False
    try:
        _ = completion_manifest(parts)
    except:
        failed = True
    assert_true(failed)
    print("multipart ordering, XML escaping, and duplicate rejection passed")
