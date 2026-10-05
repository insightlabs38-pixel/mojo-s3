from std.os import getenv
from std.testing import assert_equal, assert_true
from mojo_s3 import (
    CredentialSource,
    CredentialCache,
    Credentials,
    CredentialSnapshot,
)
from mojo_s3.identity import identity_clock


def main() raises:
    var endpoint = getenv("S3_ROLE_ENDPOINT")
    var source = CredentialSource.static(
        Credentials(
            "fixture-source", "fixture-source-secret", "fixture-source-token"
        )
    )
    var role = CredentialSource.assume_role(
        source,
        "arn:aws:iam::123456789012:role/fixture",
        "fixture-session",
        external_id="fixture-external",
        duration_seconds=900,
        endpoint=endpoint + "/assume",
        local_fixture=True,
    )
    var cache = CredentialCache(role)
    var first = cache.resolve()
    assert_equal(first.access_key, "assumed-key-1")
    var independent = cache.copy()
    cache.snapshot = CredentialSnapshot(first.copy(), identity_clock() + 1)
    assert_equal(cache.resolve().access_key, "assumed-key-2")
    assert_equal(independent.resolve().access_key, "assumed-key-1")
    var container = CredentialSource(
        "container", endpoint + "/source", local_fixture=True
    )
    var dynamic = CredentialCache(
        CredentialSource.assume_role(
            container,
            "arn:aws:iam::123456789012:role/fixture",
            "fixture-session",
            endpoint=endpoint + "/dynamic",
            local_fixture=True,
        )
    )
    assert_equal(dynamic.resolve().access_key, "dynamic-role-1")
    # Force both caches into their refresh windows; neither may sign stale identity.
    var description = dynamic.source._role_source.value().copy()
    description.snapshot = CredentialSnapshot(
        Credentials("old-source", "old-secret", "old-token"),
        identity_clock() + 1,
    )
    dynamic.source._role_source = description^
    dynamic.snapshot = None
    assert_equal(dynamic.resolve().access_key, "dynamic-role-2")
    for suffix in ["denied", "malformed", "expired"]:
        var failure = CredentialCache(
            CredentialSource.assume_role(
                source,
                "arn:aws:iam::123456789012:role/fixture",
                "fixture-session",
                endpoint=endpoint + "/" + suffix,
                local_fixture=True,
            )
        )
        var failed = False
        try:
            _ = failure.resolve()
        except:
            failed = True
        assert_true(failed)
        if suffix == "denied":
            assert_equal(failure.source.last_error.value().code, "AccessDenied")
            assert_equal(
                failure.source.last_error.value().request_id, "fixture-request"
            )
    var rejected = False
    try:
        _ = CredentialSource.assume_role(
            role, "arn:aws:iam::123456789012:role/fixture"
        )
    except:
        rejected = True
    assert_true(rejected)
    for session in ["x", "bad\nname", "bad/name"]:
        rejected = False
        try:
            _ = CredentialSource.assume_role(
                source, "arn:aws:iam::123456789012:role/fixture", session
            )
        except:
            rejected = True
        assert_true(rejected)
    print(
        "Signed native AssumeRole, nested source refresh, independent caches and fail-closed controls passed"
    )
