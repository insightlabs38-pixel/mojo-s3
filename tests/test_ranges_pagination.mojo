from std.collections import List
from std.testing import assert_equal, assert_true
from mojo_s3.objects import (
    ObjectRange,
    ObjectStore,
    ObjectMetadata,
    ObjectInfo,
    PutOptions,
    PutResult,
    GetResult,
    ListOptions,
    ListResult,
    ListPaginator,
)
from mojo_s3.client import validate_range_response
from mojo_s3.http import HttpResponse
from mojo_s3.protocol import Field
from mojo_s3.crypto import bytes_of


struct FixtureStore(ObjectStore):
    var calls: Int
    var mode: Int

    def __init__(out self, mode: Int = 0):
        self.calls = 0
        self.mode = mode

    def list(
        mut self, bucket: String, options: ListOptions = ListOptions()
    ) raises -> ListResult:
        assert_equal(bucket, "bucket")
        assert_equal(options.prefix, "folder/")
        assert_equal(options.delimiter, "/")
        assert_equal(options.max_keys, 2)
        self.calls += 1
        if self.calls == 1:
            assert_equal(options.continuation_token, "seed")
            var token = "next"
            if self.mode == 1:
                token = ""
            elif self.mode == 2:
                token = "seed"
            var objects: List[ObjectInfo] = [
                ObjectInfo("folder/a", 1, "etag", "date")
            ]
            var prefixes: List[String] = ["folder/sub/"]
            return ListResult(
                objects^,
                prefixes^,
                True,
                token,
            )
        assert_equal(options.continuation_token, "next")
        return ListResult(List[ObjectInfo](), List[String](), False, "")

    def put(
        mut self,
        bucket: String,
        key: String,
        data: List[UInt8],
        options: PutOptions = PutOptions(),
    ) raises -> PutResult:
        raise Error("Unused fixture method")

    def get(mut self, bucket: String, key: String) raises -> GetResult:
        raise Error("Unused fixture method")

    def head(mut self, bucket: String, key: String) raises -> ObjectMetadata:
        raise Error("Unused fixture method")

    def exists(mut self, bucket: String, key: String) raises -> Bool:
        raise Error("Unused fixture method")

    def delete(mut self, bucket: String, key: String) raises:
        raise Error("Unused fixture method")

    def get_range(
        mut self, bucket: String, key: String, requested: ObjectRange
    ) raises -> GetResult:
        raise Error("Unused fixture method")


def response(
    content_range: String,
    body: String = "abc",
    length: String = "3",
    status: Int = 206,
) raises -> HttpResponse:
    var headers: List[Field] = [
        Field("content-range", content_range),
        Field("content-length", length),
    ]
    return HttpResponse(
        status,
        headers^,
        bytes_of(body),
    )


def reject(
    requested: ObjectRange,
    content_range: String,
    body: String = "abc",
    length: String = "3",
    status: Int = 206,
) raises:
    var failed = False
    try:
        _ = validate_range_response(
            requested, response(content_range, body, length, status)
        )
    except:
        failed = True
    assert_true(failed)


def main() raises:
    assert_equal(ObjectRange.suffix(3).header(), "bytes=-3")
    assert_equal(ObjectRange(2).header(), "bytes=2-")
    assert_equal(ObjectRange(2, 4).header(), "bytes=2-4")
    for length in [0, -1]:
        var failed = False
        try:
            _ = ObjectRange.suffix(length)
        except:
            failed = True
        assert_true(failed)
    assert_equal(
        validate_range_response(
            ObjectRange.suffix(3), response("bytes 7-9/10")
        ).size,
        10,
    )
    assert_equal(
        validate_range_response(
            ObjectRange.suffix(30), response("bytes 0-2/3")
        ).size,
        3,
    )
    assert_equal(
        validate_range_response(
            ObjectRange.suffix(1), response("bytes 9-9/10", "a", "1")
        ).size,
        10,
    )
    assert_equal(
        validate_range_response(
            ObjectRange(2, 20), response("bytes 2-4/5")
        ).size,
        5,
    )
    assert_equal(
        validate_range_response(ObjectRange(2), response("bytes 2-4/5")).size, 5
    )
    reject(ObjectRange.suffix(3), "bytes 6-8/10")
    reject(ObjectRange.suffix(3), "bytes 0-0/0", "a", "1")
    reject(ObjectRange.suffix(3), "bytes 7-9/*")
    reject(ObjectRange.suffix(3), "bytes 7-9/10", "ab", "2")
    reject(ObjectRange.suffix(3), "bytes 7-9/10", "abc", "4")
    reject(ObjectRange.suffix(3), "bytes 7-9/10", "abc", "3", 200)
    reject(ObjectRange(2, 4), "bytes 2-5/6", "abcd", "4")
    var store = FixtureStore()
    var paginator = ListPaginator(
        "bucket", ListOptions("folder/", "/", 2, "seed")
    )
    var first = paginator.next_page(store)
    assert_equal(first.objects[0].key, "folder/a")
    assert_equal(first.prefixes[0], "folder/sub/")
    assert_equal(first.next_token, "next")
    assert_true(first.truncated)
    assert_true(not paginator.done)
    var last = paginator.next_page(store)
    assert_true(not last.truncated)
    assert_true(paginator.done)
    assert_equal(paginator.pages_loaded, 2)
    var failed = False
    try:
        _ = paginator.next_page(store)
    except:
        failed = True
    assert_true(failed)
    assert_equal(store.calls, 2)
    for mode in [1, 2]:
        var bad_store = FixtureStore(mode)
        var bad_paginator = ListPaginator(
            "bucket", ListOptions("folder/", "/", 2, "seed")
        )
        failed = False
        try:
            _ = bad_paginator.next_page(bad_store)
        except:
            failed = True
        assert_true(failed)
        assert_equal(bad_paginator.pages_loaded, 0)
        assert_equal(bad_paginator.options.continuation_token, "seed")
        assert_true(not bad_paginator.done)
    var limited_store = FixtureStore()
    var limited = ListPaginator(
        "bucket", ListOptions("folder/", "/", 2, "seed"), max_pages=1
    )
    _ = limited.next_page(limited_store)
    failed = False
    try:
        _ = limited.next_page(limited_store)
    except:
        failed = True
    assert_true(failed)
    assert_equal(limited_store.calls, 1)
    print("suffix ranges, response coherence, and bounded pagination passed")
