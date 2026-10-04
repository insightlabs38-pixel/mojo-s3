"""Provider-neutral contract: implementations only need ObjectStore."""
from std.collections import List
from std.testing import assert_equal, assert_true, assert_false
from mojo_s3.objects import ObjectStore, PutOptions, ListOptions, ObjectRange
from mojo_s3.protocol import Field, get_header
from mojo_s3.crypto import bytes_of, sha256_hex


def run_contract[
    T: ObjectStore
](mut store: T, bucket: String, prefix: String) raises:
    var keys: List[String] = [
        "simple",
        "dir/file",
        "space key",
        "plus+key",
        "percent%key",
        "question?key",
        "hash#key",
        "ampersand&key",
        "equals=key",
        "Unicode-é-雪",
        "literal%2Fkey",
    ]
    var long_key = String()
    for component in range(4):
        if component:
            long_key += "/"
        for _ in range(200):
            long_key += "k"
    keys.append(long_key)
    var data = List[UInt8](length=256 * 1024, fill=0)
    for i in range(len(data)):
        data[i] = UInt8((i * 131 + 17) % 256)
    var options = PutOptions("application/x-mojo-test")
    options.metadata.append(Field("Project", "native mojo"))
    options.metadata.append(Field("user_label", "second field"))
    try:
        for key in keys:
            var name = prefix + key
            var put = store.put(bucket, name, data, options)
            assert_true(Bool(put.etag))
            var get = store.get(bucket, name)
            assert_equal(sha256_hex(get.data), sha256_hex(data))
            assert_equal(get.metadata.content_type, "application/x-mojo-test")
            assert_equal(
                get_header(get.metadata.metadata, "project"), "native mojo"
            )
            var head = store.head(bucket, name)
            assert_equal(head.size, len(data))
            assert_true(store.exists(bucket, name))
        _ = store.put(bucket, prefix + "empty", List[UInt8]())
        assert_equal(len(store.get(bucket, prefix + "empty").data), 0)
        _ = store.put(bucket, prefix + "overwrite", bytes_of("old"))
        _ = store.put(bucket, prefix + "overwrite", bytes_of("new"))
        assert_equal(
            sha256_hex(store.get(bucket, prefix + "overwrite").data),
            sha256_hex(bytes_of("new")),
        )
        var count = 0
        var token = String()
        var seen = List[String]()
        while True:
            var page = store.list(bucket, ListOptions(prefix, "", 3, token))
            count += len(page.objects)
            for o in page.objects:
                for prior in seen:
                    assert_false(prior == o.key)
                seen.append(o.key)
            if not page.truncated:
                break
            assert_true(page.next_token != token)
            token = page.next_token
            assert_true(count <= len(keys) + 2)
        assert_equal(count, len(keys) + 2)
        var dirs = store.list(bucket, ListOptions(prefix, "/"))
        assert_true(len(dirs.prefixes) > 0)
        var name = prefix + keys[0]
        var first = store.get_range(bucket, name, ObjectRange(0, 0))
        assert_equal(len(first.data), 1)
        assert_equal(first.data[0], data[0])
        var last = store.get_range(bucket, name, ObjectRange(len(data) - 1))
        assert_equal(len(last.data), 1)
        assert_equal(last.data[0], data[len(data) - 1])
        var middle = store.get_range(bucket, name, ObjectRange(123, 1024))
        assert_equal(len(middle.data), 902)
        for i in range(len(middle.data)):
            assert_equal(middle.data[i], data[123 + i])
        var full = store.get_range(bucket, name, ObjectRange(0, len(data) + 10))
        assert_equal(sha256_hex(full.data), sha256_hex(data))
        var failed = False
        try:
            _ = store.get_range(bucket, name, ObjectRange(len(data) + 1))
        except:
            failed = True
        assert_true(failed)
        assert_false(store.exists(bucket, prefix + "missing"))
        store.delete(bucket, prefix + "missing")
    except e:
        for key in keys:
            try:
                store.delete(bucket, prefix + key)
            except:
                pass
        for key in ["empty", "overwrite"]:
            try:
                store.delete(bucket, prefix + key)
            except:
                pass
        raise e^
    for key in keys:
        store.delete(bucket, prefix + key)
        assert_false(store.exists(bucket, prefix + key))
    store.delete(bucket, prefix + "empty")
    store.delete(bucket, prefix + "overwrite")
    print(
        "provider-neutral CRUD/list/pagination/range/edge-key contract passed"
    )
