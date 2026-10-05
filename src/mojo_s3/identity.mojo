"""Experimental owned refreshing workload credentials; no global cache/state."""
from std.collections import List
from std.ffi import external_call
from std.memory import Pointer
from std.io import FileHandle
from mojo_s3.signing import Credentials
from mojo_s3.credentials import validate_credentials
from mojo_s3.http import CurlTransport, HttpRequest, HttpResponse
from mojo_s3.protocol import Field, canonical_query, uri_encode, get_header
from mojo_s3.crypto import bytes_of
from mojo_s3.xml import parse_xml, child_text
from mojo_s3.identity_json import CredentialJson

comptime IdentityRaw = Pointer[UInt8, MutUntrackedOrigin]


def identity_clock() raises -> Int:
    var now = external_call["time", Int64](Optional[IdentityRaw](None))
    if now < 0:
        raise Error("Credential clock unavailable")
    return Int(now)


def expiration_seconds(text: String) raises -> Int:
    if text.byte_length() != 20 or not text.endswith("Z"):
        raise Error("Credential expiration must be a UTC second timestamp")
    var input_text = text
    var tm = List[UInt8](length=128, fill=0)
    var format = "%Y-%m-%dT%H:%M:%SZ"
    var end = external_call["strptime", Optional[IdentityRaw]](
        input_text.as_c_string_span(),
        format.as_c_string_span(),
        tm.unsafe_ptr(),
    )
    if not end or end.value()[] != 0:
        raise Error("Invalid credential expiration")
    var seconds = external_call["timegm", Int64](tm.unsafe_ptr())
    var roundtrip = List[UInt8](length=32, fill=0)
    var n = external_call["strftime", Int](
        roundtrip.unsafe_ptr(),
        Int(32),
        format.as_c_string_span(),
        tm.unsafe_ptr(),
    )
    if (
        seconds < 0
        or n != 20
        or String(from_utf8=Span(unsafe_ptr=roundtrip.unsafe_ptr(), length=n))
        != text
    ):
        raise Error("Invalid credential expiration")
    return Int(seconds)


@fieldwise_init
struct CredentialSnapshot(Copyable, Movable):
    var credentials: Credentials
    var expiration: Int


def response_text(response: HttpResponse) raises -> String:
    if response.status != 200:
        raise Error("Credential endpoint request failed")
    return String(
        from_utf8=Span(
            unsafe_ptr=response.body.unsafe_ptr(), length=len(response.body)
        )
    )


def credential_field(fields: List[Field], name: String) -> String:
    for field in fields:
        if field.name == name:
            return field.value
    return ""


def json_snapshot(text: String) raises -> CredentialSnapshot:
    var parser = CredentialJson(text)
    var fields = parser.fields()
    var code = credential_field(fields, "Code")
    if code and code != "Success":
        raise Error("Credential endpoint returned a failure")
    var credentials = Credentials(
        credential_field(fields, "AccessKeyId"),
        credential_field(fields, "SecretAccessKey"),
        credential_field(fields, "Token"),
    )
    validate_credentials(credentials)
    if not credentials.session_token:
        raise Error("Workload credentials require a session token")
    return CredentialSnapshot(
        credentials^, expiration_seconds(credential_field(fields, "Expiration"))
    )


def sts_snapshot(text: String) raises -> CredentialSnapshot:
    var nodes = parse_xml(text)
    if nodes[0].name != "AssumeRoleWithWebIdentityResponse":
        raise Error("Unexpected STS web identity response")
    var found = -1
    for i in range(len(nodes)):
        if (
            nodes[i].name == "Credentials"
            and nodes[i].parent >= 0
            and nodes[nodes[i].parent].name == "AssumeRoleWithWebIdentityResult"
            and nodes[nodes[i].parent].parent == 0
        ):
            if found >= 0:
                raise Error("Duplicate STS credentials")
            found = i
    if found < 0:
        raise Error("STS response has no credentials")
    var credentials = Credentials(
        child_text(nodes, found, "AccessKeyId"),
        child_text(nodes, found, "SecretAccessKey"),
        child_text(nodes, found, "SessionToken"),
    )
    validate_credentials(credentials)
    if not credentials.session_token:
        raise Error("STS response has no session token")
    return CredentialSnapshot(
        credentials^, expiration_seconds(child_text(nodes, found, "Expiration"))
    )


def trusted_identity_url(
    url: String, kind: String, allow_local_fixture: Bool
) raises:
    if "@" in url or "#" in url or "?" in url:
        raise Error("Credential endpoint URL contains unsupported components")
    for b in url.as_bytes():
        if b < 33 or b == 127:
            raise Error("Invalid credential endpoint URL")
    if url.startswith("https://") and kind != "imds":
        return
    var allowed = (
        [
            "http://169.254.170.2",
            "http://169.254.170.23",
            "http://[fd00:ec2::23]",
        ] if kind
        == "container" else [
            "http://169.254.169.254",
            "http://[fd00:ec2::254]",
        ] if kind
        == "imds" else List[String]()
    )
    for prefix in allowed:
        if url == prefix or url.startswith(prefix + "/"):
            return
    if allow_local_fixture and (
        url.startswith("http://127.0.0.1:")
        or url.startswith("http://localhost:")
    ):
        # The explicit fixture flag never comes from ambient environment.
        return
    raise Error(
        "Untrusted credential endpoint; use HTTPS or the supported metadata address"
    )


struct CredentialSource(Copyable, Movable):
    var kind: String
    var endpoint: String
    var role_arn: String
    var token_file: String
    var session_name: String
    var authorization: String
    var ca_bundle: String
    var local_fixture: Bool

    def __init__(
        out self,
        kind: String = "",
        endpoint: String = "",
        role_arn: String = "",
        token_file: String = "",
        session_name: String = "mojo-s3",
        authorization: String = "",
        ca_bundle: String = "",
        local_fixture: Bool = False,
    ):
        self.kind = kind
        self.endpoint = endpoint
        self.role_arn = role_arn
        self.token_file = token_file
        self.session_name = session_name
        self.authorization = authorization
        self.ca_bundle = ca_bundle
        self.local_fixture = local_fixture

    def fetch(self) raises -> CredentialSnapshot:
        if self.kind not in ["web_identity", "container", "imds"]:
            raise Error("Unsupported workload credential source")
        trusted_identity_url(self.endpoint, self.kind, self.local_fixture)
        var transport = CurlTransport(
            timeout_ms=5000,
            connect_timeout_ms=1000,
            max_response_bytes=65536,
            verify_tls=True,
            ca_bundle=self.ca_bundle,
        )
        if self.kind == "web_identity":
            if (
                not self.role_arn
                or not self.token_file
                or not self.session_name
            ):
                raise Error(
                    "Web identity requires role, token file and session name"
                )
            var file = FileHandle(self.token_file, "r")
            var raw_token = file.read(65537)
            if raw_token.byte_length() > 65536:
                raise Error("Web identity token file exceeds limit")
            var token = String(raw_token.strip())
            if not token or token.byte_length() > 65536:
                raise Error("Invalid web identity token file")
            var form: List[Field] = [
                Field("Action", "AssumeRoleWithWebIdentity"),
                Field("Version", "2011-06-15"),
                Field("RoleArn", self.role_arn),
                Field("RoleSessionName", self.session_name),
                Field("WebIdentityToken", token),
            ]
            var headers: List[Field] = [
                Field("content-type", "application/x-www-form-urlencoded")
            ]
            return sts_snapshot(
                response_text(
                    transport.send(
                        HttpRequest(
                            "POST",
                            self.endpoint,
                            headers^,
                            bytes_of(canonical_query(form)),
                        )
                    )
                )
            )
        var headers = List[Field]()
        if self.kind == "container":
            if self.authorization:
                headers.append(Field("authorization", self.authorization))
            return json_snapshot(
                response_text(
                    transport.send(
                        HttpRequest(
                            "GET", self.endpoint, headers^, List[UInt8]()
                        )
                    )
                )
            )
        var token_headers: List[Field] = [
            Field("x-aws-ec2-metadata-token-ttl-seconds", "60")
        ]
        var token = response_text(
            transport.send(
                HttpRequest(
                    "PUT",
                    self.endpoint + "/latest/api/token",
                    token_headers^,
                    List[UInt8](),
                )
            )
        )
        if not token or token.byte_length() > 1024:
            raise Error("Invalid IMDSv2 token")
        headers.append(Field("x-aws-ec2-metadata-token", token))
        var base = self.endpoint + "/latest/meta-data/iam/security-credentials/"
        var role = String(
            response_text(
                transport.send(
                    HttpRequest("GET", base, headers.copy(), List[UInt8]())
                )
            ).strip()
        )
        if not role or "\n" in role or "/" in role or role.byte_length() > 256:
            raise Error("IMDSv2 must return exactly one bounded role name")
        return json_snapshot(
            response_text(
                transport.send(
                    HttpRequest(
                        "GET", base + uri_encode(role), headers^, List[UInt8]()
                    )
                )
            )
        )


struct CredentialCache(Copyable, Movable):
    var source: CredentialSource
    var snapshot: Optional[CredentialSnapshot]
    var refresh_before: Int

    def __init__(
        out self,
        source: CredentialSource = CredentialSource(),
        refresh_before: Int = 300,
    ):
        self.source = source.copy()
        self.snapshot = None
        self.refresh_before = refresh_before

    def resolve_at(mut self, now: Int) raises -> Credentials:
        if now < 0 or self.refresh_before < 0 or self.refresh_before > 3600:
            raise Error("Invalid credential refresh timing")
        if (
            self.snapshot
            and self.snapshot.value().expiration > now
            and self.snapshot.value().expiration - now > self.refresh_before
        ):
            return self.snapshot.value().credentials.copy()
        # Fail closed on refresh failure, retaining the old cache only for inspection.
        var fresh = self.source.fetch()
        if (
            fresh.expiration <= now
            or fresh.expiration - now <= self.refresh_before
        ):
            raise Error("Refreshed credentials expire too soon")
        self.snapshot = Optional(fresh^)
        return self.snapshot.value().credentials.copy()

    def resolve(mut self) raises -> Credentials:
        return self.resolve_at(identity_clock())


def workload_source_from_env() raises -> CredentialSource:
    """Explicit opt-in to network providers; static default chain stays local."""
    from std.os import getenv

    var role = getenv("AWS_ROLE_ARN")
    var file = getenv("AWS_WEB_IDENTITY_TOKEN_FILE")
    if role or file:
        if not role or not file:
            raise Error("Web identity environment requires role and token file")
        var region = getenv(
            "AWS_REGION", getenv("AWS_DEFAULT_REGION", "us-east-1")
        )
        for b in region.as_bytes():
            if not (b >= 97 and b <= 122 or b >= 48 and b <= 57 or b == 45):
                raise Error("Invalid STS region")
        var suffix = ".amazonaws.com.cn" if region.startswith(
            "cn-"
        ) else ".amazonaws.com"
        return CredentialSource(
            "web_identity",
            "https://sts." + region + suffix,
            role,
            file,
            getenv("AWS_ROLE_SESSION_NAME", "mojo-s3"),
        )
    var relative = getenv("AWS_CONTAINER_CREDENTIALS_RELATIVE_URI")
    var full = getenv("AWS_CONTAINER_CREDENTIALS_FULL_URI")
    if relative or full:
        if relative and not relative.startswith("/"):
            raise Error("Container relative URI must begin with slash")
        var endpoint = "http://169.254.170.2" + relative if relative else full
        trusted_identity_url(endpoint, "container", False)
        var authorization = getenv("AWS_CONTAINER_AUTHORIZATION_TOKEN")
        var token_file = getenv("AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE")
        if token_file:
            var handle = FileHandle(token_file, "r")
            var raw_authorization = handle.read(65537)
            if raw_authorization.byte_length() > 65536:
                raise Error("Container authorization file exceeds limit")
            authorization = String(raw_authorization.strip())
        return CredentialSource(
            "container", endpoint, authorization=authorization
        )
    if (
        getenv("S3_ALLOW_IMDSV2") == "1"
        and getenv("AWS_EC2_METADATA_DISABLED") != "true"
    ):
        return CredentialSource("imds", "http://169.254.169.254")
    raise Error("No explicitly enabled workload credential source")
