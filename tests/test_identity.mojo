from std.testing import assert_equal, assert_true
from mojo_s3.identity import (
    expiration_seconds,
    json_snapshot,
    sts_snapshot,
    CredentialCache,
    CredentialSource,
    trusted_identity_url,
)
from mojo_s3.identity_json import CredentialJson


def main() raises:
    assert_equal(expiration_seconds("1970-01-01T00:00:00Z"), 0)
    assert_equal(expiration_seconds("2026-10-05T00:00:00Z"), 1791158400)
    var snapshot = json_snapshot(
        '{"AccessKeyId":"key","SecretAccessKey":"secret","Token":"token","Expiration":"2026-10-05T00:00:00Z","Code":"Success"}'
    )
    assert_equal(snapshot.credentials.session_token, "token")
    var parser = CredentialJson('{"escaped":"\\uD83D\\uDE00","slash":"a\\/b"}')
    var fields = parser.fields()
    assert_equal(fields[0].value, "😀")
    assert_equal(fields[1].value, "a/b")
    for bad in [
        '{"AccessKeyId":"a","AccessKeyId":"b"}',
        '{"a":"b",}',
        '{"a":2}',
        '{"a":"b"}trailing',
        '{"a":"\\uD800"}',
    ]:
        var failed = False
        try:
            var invalid = CredentialJson(bad)
            _ = invalid.fields()
        except:
            failed = True
        assert_true(failed)
    for date in [
        "2026-02-30T00:00:00Z",
        "2026-10-05T00:00:00+00:00",
        "expired",
    ]:
        var failed = False
        try:
            _ = expiration_seconds(date)
        except:
            failed = True
        assert_true(failed)
    var cache = CredentialCache()
    cache.snapshot = snapshot.copy()
    assert_equal(cache.resolve_at(1791150000).access_key, "key")
    var copied = cache.copy()
    cache.snapshot = None
    assert_equal(copied.resolve_at(1791150000).access_key, "key")
    var failed = False
    try:
        _ = copied.resolve_at(1791158400)
    except:
        failed = True
    assert_true(failed)
    for url in [
        "http://example.com/credentials",
        "http://169.254.170.2.evil/",
        "https://user@host/",
        "http://127.0.0.1:1/",
    ]:
        failed = False
        try:
            trusted_identity_url(url, "container", False)
        except:
            failed = True
        assert_true(failed)
    trusted_identity_url("http://169.254.170.2/credentials", "container", False)
    print(
        "Credential JSON, expiration, owned cache and endpoint trust fixtures passed"
    )
