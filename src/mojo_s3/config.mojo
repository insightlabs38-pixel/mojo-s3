"""Explicit/environment configuration and a single UTC clock entry point."""
from std.os import getenv
from std.ffi import external_call
from std.memory import Pointer
from std.collections import List
from mojo_s3.signing import Credentials
from mojo_s3.identity import CredentialCache, CredentialSource
from mojo_s3.credentials import (
    EnvironmentCredentials,
    default_credentials,
    aws_profile,
    shared_file_path,
    read_profile_file,
    profile_value,
)


struct S3Config(Copyable, Movable):
    var endpoint: String
    var region: String
    var credentials: Credentials
    var virtual_host: Bool
    var fixed_timestamp: String
    var max_attempts: Int
    var retry_base_ms: Int
    var request_checksums: Bool
    var credential_cache: CredentialCache
    var checksum_algorithm: String

    def __init__(
        out self,
        endpoint: String,
        region: String,
        credentials: Credentials,
        virtual_host: Bool = False,
        fixed_timestamp: String = "",
        max_attempts: Int = 3,
        retry_base_ms: Int = 100,
        request_checksums: Bool = False,
    ) raises:
        if (
            max_attempts < 1
            or max_attempts > 10
            or retry_base_ms < 0
            or retry_base_ms > 60000
        ):
            raise Error("Invalid retry configuration")
        self.endpoint = endpoint
        self.region = region
        self.credentials = credentials.copy()
        self.virtual_host = virtual_host
        self.fixed_timestamp = fixed_timestamp
        self.max_attempts = max_attempts
        self.retry_base_ms = retry_base_ms
        self.request_checksums = request_checksums
        self.credential_cache = CredentialCache()
        self.checksum_algorithm = "sha256"

    def credential_snapshot(mut self) raises -> Credentials:
        if self.credential_cache.source.kind:
            return self.credential_cache.resolve()
        return self.credentials.copy()

    @staticmethod
    def with_provider(
        endpoint: String,
        region: String,
        source: CredentialSource,
        virtual_host: Bool = False,
    ) raises -> Self:
        var cache = CredentialCache(source)
        var result = Self(endpoint, region, cache.resolve(), virtual_host)
        result.credential_cache = cache^
        return result^

    @staticmethod
    def aws(
        credentials: Credentials, region: String = "us-east-1"
    ) raises -> Self:
        """AWS HTTPS endpoint defaults; generic endpoints remain explicit."""
        return Self(aws_endpoint(region), region, credentials, True)

    @staticmethod
    def from_env() raises -> Self:
        """Environment-only credentials; use from_default for AWS profile files."""
        var provider = EnvironmentCredentials()
        var region = environment_region()
        var endpoint = getenv("S3_ENDPOINT")
        if not endpoint:
            endpoint = aws_endpoint(region)
        return Self(
            endpoint,
            region,
            provider.resolve(),
            environment_virtual_host(),
        )

    @staticmethod
    def from_default() raises -> Self:
        """Environment then shared credentials/config file static credentials."""
        var region = environment_region(False)
        if not region:
            region = profile_value(
                read_profile_file(
                    shared_file_path(True), Bool(getenv("AWS_CONFIG_FILE"))
                ),
                aws_profile(),
                "region",
                True,
            )
        if not region:
            region = "us-east-1"
        var endpoint = getenv("S3_ENDPOINT")
        if not endpoint:
            endpoint = aws_endpoint(region)
        return Self(
            endpoint,
            region,
            default_credentials(),
            environment_virtual_host(),
        )


def environment_region(use_default: Bool = True) -> String:
    return getenv(
        "S3_REGION",
        getenv(
            "AWS_REGION",
            getenv("AWS_DEFAULT_REGION", "us-east-1" if use_default else ""),
        ),
    )


def environment_virtual_host() raises -> Bool:
    var style = getenv(
        "S3_FORCE_PATH_STYLE", "true" if getenv("S3_ENDPOINT") else "false"
    )
    if style != "true" and style != "false":
        raise Error("S3_FORCE_PATH_STYLE must be true or false")
    return style == "false"


def aws_endpoint(
    region: String, dual_stack: Bool = False, fips: Bool = False
) raises -> String:
    if not region:
        raise Error("AWS region is required")
    for b in region.as_bytes():
        if not (b >= 97 and b <= 122 or b >= 48 and b <= 57 or b == 45):
            raise Error("Invalid AWS region")
    var suffix = ".amazonaws.com.cn" if region.startswith(
        "cn-"
    ) else ".amazonaws.com"
    if region.startswith("cn-") and fips:
        raise Error("FIPS endpoints are not supported for the China partition")
    return (
        "https://"
        + ("s3-fips" if fips else "s3")
        + (".dualstack" if dual_stack else "")
        + "."
        + region
        + suffix
    )


comptime Raw = Pointer[UInt8, MutUntrackedOrigin]


from mojo_s3.clock import utc_seconds, utc_timestamp
