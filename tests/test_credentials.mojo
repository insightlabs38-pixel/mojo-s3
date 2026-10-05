"""Deterministic credential/profile fixtures; never needs network or real secrets."""
from std.testing import assert_equal, assert_true
from std.os import setenv, unsetenv
from std.tempfile import NamedTemporaryFile
from mojo_s3.signing import Credentials
from mojo_s3.credentials import (
    StaticCredentials,
    SharedFileCredentials,
    default_credentials,
    environment_credentials,
    profile_credentials,
    profile_value,
)
from mojo_s3.config import S3Config, aws_endpoint


def main() raises:
    var provider = StaticCredentials(Credentials("fixture", "secret", "token"))
    assert_equal(provider.resolve().session_token, "token")
    var env = environment_credentials(
        "s3", "secret", "s3token", "aws", "other", "awstoken"
    )
    assert_equal(env.value().access_key, "s3")
    assert_equal(env.value().session_token, "s3token")
    env = environment_credentials("", "", "", "aws", "secret", "token")
    assert_equal(env.value().access_key, "aws")
    assert_true(not environment_credentials("", "", "", "", "", ""))
    var failed = False
    try:
        _ = environment_credentials("s3", "", "", "aws", "secret", "")
    except:
        failed = True
    assert_true(failed)
    failed = False
    try:
        _ = environment_credentials("", "", "orphan", "aws", "secret", "")
    except:
        failed = True
    assert_true(failed)
    var fixture = "# fixture\r\n[default]\r\naws_access_key_id = default-key\r\naws_secret_access_key = default-secret\r\n[ci]\naws_access_key_id = ci-key\naws_secret_access_key = a#b;c=secret\naws_session_token = session\n"
    var credentials = profile_credentials(fixture, "ci")
    assert_equal(credentials.value().secret_key, "a#b;c=secret")
    assert_equal(credentials.value().session_token, "session")
    assert_equal(profile_credentials(fixture).value().access_key, "default-key")
    assert_true(not profile_credentials(fixture, "missing"))
    var config = "[profile ci]\nregion=eu-west-1\naws_access_key_id=ci\naws_secret_access_key=secret\n[default]\nregion=us-east-2\n"
    assert_equal(profile_value(config, "ci", "region", True), "eu-west-1")
    assert_equal(
        profile_credentials(config, "ci", True).value().access_key, "ci"
    )
    assert_true(not profile_credentials(config, "ci"))
    for invalid in [
        "[default]\naws_access_key_id=key\n",
        "[default]\naws_access_key_id=key\naws_secret_access_key=secret\naws_access_key_id=other\n",
        "[default]\naws_access_key_id=key\naws_secret_access_key=secret\n[default]\n",
        "[default]\naws_session_token=token\n",
        "[default\naws_access_key_id=key\n",
    ]:
        failed = False
        try:
            _ = profile_credentials(invalid)
        except:
            failed = True
        assert_true(failed)
    assert_equal(
        aws_endpoint("eu-west-1"), "https://s3.eu-west-1.amazonaws.com"
    )
    assert_equal(
        aws_endpoint("cn-north-1"), "https://s3.cn-north-1.amazonaws.com.cn"
    )
    var aws = S3Config.aws(provider.resolve(), "eu-west-1")
    assert_true(aws.virtual_host)
    failed = False
    try:
        _ = aws_endpoint("region/evil")
    except:
        failed = True
    assert_true(failed)
    # Isolate the subprocess from developer/CI credentials before chain fixtures.
    for name in [
        "S3_ACCESS_KEY",
        "S3_SECRET_KEY",
        "S3_SESSION_TOKEN",
        "AWS_ACCESS_KEY_ID",
        "AWS_SECRET_ACCESS_KEY",
        "AWS_SESSION_TOKEN",
        "S3_REGION",
        "AWS_REGION",
        "AWS_DEFAULT_REGION",
        "S3_ENDPOINT",
        "S3_FORCE_PATH_STYLE",
        "AWS_DEFAULT_PROFILE",
    ]:
        assert_true(unsetenv(name))
    with NamedTemporaryFile() as credential_file:
        credential_file.write(fixture)
        with NamedTemporaryFile() as config_file:
            config_file.write(config)
            assert_true(
                setenv("AWS_SHARED_CREDENTIALS_FILE", credential_file.name)
            )
            assert_true(setenv("AWS_CONFIG_FILE", config_file.name))
            assert_true(setenv("AWS_PROFILE", "ci"))
            var shared = SharedFileCredentials(credential_file.name, "ci")
            assert_equal(shared.resolve().access_key, "ci-key")
            assert_equal(default_credentials().access_key, "ci-key")
            var resolved = S3Config.from_default()
            assert_equal(resolved.region, "eu-west-1")
            assert_equal(
                resolved.endpoint, "https://s3.eu-west-1.amazonaws.com"
            )
            assert_true(setenv("AWS_ACCESS_KEY_ID", "env-key"))
            assert_true(setenv("AWS_SECRET_ACCESS_KEY", "env-secret"))
            assert_true(setenv("AWS_DEFAULT_REGION", "us-west-2"))
            assert_equal(default_credentials().access_key, "env-key")
            assert_equal(S3Config.from_env().region, "us-west-2")
            assert_true(setenv("S3_ENDPOINT", "http://localhost:9000"))
            assert_true(setenv("S3_REGION", "custom_region"))
            assert_equal(S3Config.from_env().endpoint, "http://localhost:9000")
            assert_equal(S3Config.from_default().region, "custom_region")
            assert_true(not S3Config.from_env().virtual_host)
            assert_true(unsetenv("S3_ENDPOINT"))
            assert_true(unsetenv("S3_REGION"))
            assert_true(setenv("S3_ACCESS_KEY", "incomplete"))
            failed = False
            try:
                _ = default_credentials()
            except:
                failed = True
            assert_true(failed)
            assert_true(unsetenv("S3_ACCESS_KEY"))
            assert_true(unsetenv("AWS_ACCESS_KEY_ID"))
            assert_true(unsetenv("AWS_SECRET_ACCESS_KEY"))
            assert_true(setenv("AWS_PROFILE", "missing"))
            failed = False
            try:
                _ = default_credentials()
            except:
                failed = True
            assert_true(failed)
    print(
        "Credential provider, profile parsing, and AWS defaults fixtures passed"
    )
