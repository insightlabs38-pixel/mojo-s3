from std.os import getenv
from std.testing import assert_true, assert_equal
from mojo_s3 import (
    S3Store,
    S3Config,
    CredentialSource,
    CredentialCache,
    CredentialSnapshot,
    Credentials,
)
from mojo_s3.identity import identity_clock


def main() raises:
    var endpoint = getenv("S3_IDENTITY_ENDPOINT")
    var token_file = getenv("S3_IDENTITY_TOKEN_FILE")
    var web = CredentialSource(
        "web_identity",
        endpoint + "/sts",
        "arn:aws:iam::123456789012:role/fixture",
        token_file,
        local_fixture=True,
    )
    assert_true(Bool(web.fetch().credentials.session_token))
    var imds = CredentialSource("imds", endpoint, local_fixture=True)
    assert_true(Bool(imds.fetch().credentials.session_token))
    var source = CredentialSource(
        "container",
        endpoint + "/credentials",
        authorization="fixture-auth",
        local_fixture=True,
    )
    var config = S3Config.with_provider(endpoint, "us-east-1", source)
    config.retry_base_ms = 0
    config.credential_cache.snapshot = CredentialSnapshot(
        Credentials("old", "old", "old"), identity_clock() + 1
    )
    var store = S3Store(config)
    var result = store.get("bucket", "refresh-retry")
    assert_equal(len(result.data), 2)
    # A copied worker config owns its cache: changing one cannot mutate another.
    var other = store.config.copy()
    store.config.credential_cache.snapshot = None
    assert_true(Bool(other.credential_cache.snapshot))
    store.config.credentials = Credentials(
        "stale-key", "stale-secret", "stale-token"
    )
    var url = store.presign("GET", "bucket", "refresh-presign", 60)
    assert_true("X-Amz-Credential=fixture-key%2F" in url)
    assert_true("stale-key" not in url)
    assert_true("X-Amz-Security-Token=fixture-token-3" in url)
    var duration_failed = False
    try:
        _ = store.presign("GET", "bucket", "refresh-presign", 4000)
    except:
        duration_failed = True
    assert_true(duration_failed)
    var retry_config = S3Config.with_provider(
        endpoint,
        "us-east-1",
        CredentialSource(
            "container", endpoint + "/retry-credentials", local_fixture=True
        ),
    )
    retry_config.retry_base_ms = 0
    retry_config.credential_cache.refresh_before = 0
    retry_config.credential_cache.snapshot = CredentialSnapshot(
        retry_config.credentials.copy(), identity_clock() + 1
    )
    var retry_store = S3Store(retry_config)
    assert_equal(
        len(retry_store.get("bucket", "expires-between-attempts").data), 2
    )
    var denied = CredentialCache(
        CredentialSource("container", endpoint + "/denied", local_fixture=True)
    )
    denied.snapshot = CredentialSnapshot(
        Credentials("old", "old", "old"), identity_clock() + 1
    )
    var failed = False
    try:
        _ = denied.resolve()
    except:
        failed = True
    assert_true(failed)
    assert_equal(denied.snapshot.value().credentials.access_key, "old")
    for suffix in ["/malformed", "/expired", "/slow"]:
        failed = False
        try:
            var faulty = CredentialCache(
                CredentialSource(
                    "container", endpoint + suffix, local_fixture=True
                )
            )
            _ = faulty.resolve()
        except:
            failed = True
        assert_true(failed)
    print(
        "Native WebIdentity/container/IMDSv2, refresh/retry, cache ownership and failures passed"
    )
