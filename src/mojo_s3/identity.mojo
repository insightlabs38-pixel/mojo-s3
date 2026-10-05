"""Experimental owned refreshing workload credentials; no global cache/state."""
from std.collections import List
from std.ffi import external_call
from std.memory import Pointer
from std.io import FileHandle
from mojo_s3.signing import Credentials, sign
from mojo_s3.credentials import validate_credentials
from mojo_s3.http import CurlTransport, HttpRequest, HttpResponse
from mojo_s3.protocol import (
    Field,
    canonical_query,
    uri_encode,
    get_header,
    Address,
)
from mojo_s3.crypto import bytes_of, sha256_hex
from mojo_s3.xml import parse_xml, child_text
from mojo_s3.clock import utc_timestamp
from mojo_s3.errors import S3Error
from mojo_s3.identity_json import CredentialJson

comptime IdentityRaw = Pointer[UInt8, MutUntrackedOrigin]


def identity_address(endpoint: String) raises -> Address:
    var split = endpoint.find("://")
    if split < 0:
        raise Error("Credential endpoint requires a URL scheme")
    var scheme = String(endpoint[byte=0:split])
    var rest = String(endpoint[byte = split + 3 :])
    var slash = rest.find("/")
    var host = rest if slash < 0 else String(rest[byte=0:slash])
    var path = "/" if slash < 0 else uri_encode(String(rest[byte=slash:]), True)
    if not host:
        raise Error("Credential endpoint host required")
    return Address(scheme + "://" + host + path, host, path)


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


def sts_snapshot(
    text: String, action: String = "AssumeRoleWithWebIdentity"
) raises -> CredentialSnapshot:
    var nodes = parse_xml(text)
    if nodes[0].name != action + "Response":
        raise Error("Unexpected STS web identity response")
    var found = -1
    for i in range(len(nodes)):
        if (
            nodes[i].name == "Credentials"
            and nodes[i].parent >= 0
            and nodes[nodes[i].parent].name == action + "Result"
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


@fieldwise_init
struct RoleSourceDescription(Copyable, Movable):
    var kind: String
    var endpoint: String
    var role_arn: String
    var token_file: String
    var session_name: String
    var authorization: String
    var ca_bundle: String
    var local_fixture: Bool
    var static_credentials: Credentials
    var snapshot: Optional[CredentialSnapshot]


def validate_role_session(
    role_arn: String,
    session_name: String,
    external_id: String,
    duration_seconds: Int,
) raises:
    if (
        not role_arn.startswith("arn:")
        or ":iam::" not in role_arn
        or ":role/" not in role_arn
        or role_arn.byte_length() > 2048
    ):
        raise Error("AssumeRole requires an IAM role ARN")
    for b in role_arn.as_bytes():
        if b < 33 or b > 126:
            raise Error("Invalid role ARN")
    if session_name.byte_length() < 2 or session_name.byte_length() > 64:
        raise Error("Role session name must contain 2..64 ASCII characters")
    for text in [session_name, external_id]:
        for b in text.as_bytes():
            if not (
                b >= 65
                and b <= 90
                or b >= 97
                and b <= 122
                or b >= 48
                and b <= 57
                or b in bytes_of("+=,.@-_:/")
            ):
                raise Error("Invalid role session or external ID character")
    if ":" in session_name or "/" in session_name:
        raise Error("Invalid role session name")
    if external_id and (
        external_id.byte_length() < 2 or external_id.byte_length() > 1224
    ):
        raise Error("External ID must contain 2..1224 ASCII characters")
    if duration_seconds != 0 and (
        duration_seconds < 900 or duration_seconds > 43200
    ):
        raise Error(
            "AssumeRole duration must be 900..43200 seconds or zero to omit"
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
    var static_credentials: Credentials
    var _role_source: Optional[RoleSourceDescription]
    var _sts_region: String
    var _external_id: String
    var _duration_seconds: Int
    var last_error: Optional[S3Error]

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
        self.static_credentials = Credentials("", "", "")
        self._role_source = None
        self._sts_region = "us-east-1"
        self._external_id = ""
        self._duration_seconds = 0
        self.last_error = None

    @staticmethod
    def static(credentials: Credentials) raises -> Self:
        validate_credentials(credentials)
        var result = Self("static")
        result.static_credentials = credentials.copy()
        return result^

    @staticmethod
    def assume_role(
        source: Self,
        role_arn: String,
        session_name: String = "mojo-s3",
        region: String = "us-east-1",
        external_id: String = "",
        duration_seconds: Int = 0,
        *,
        endpoint: String = "",
        ca_bundle: String = "",
        local_fixture: Bool = False,
    ) raises -> Self:
        validate_role_session(
            role_arn, session_name, external_id, duration_seconds
        )
        if source.kind not in ["static", "web_identity", "container", "imds"]:
            raise Error(
                "AssumeRole supports one non-role source provider; role chains/cycles are refused"
            )
        if not region:
            raise Error("STS region is required")
        for b in region.as_bytes():
            if not (b >= 97 and b <= 122 or b >= 48 and b <= 57 or b == 45):
                raise Error("Invalid STS region")
        var suffix = ".amazonaws.com.cn" if region.startswith(
            "cn-"
        ) else ".amazonaws.com"
        var url = endpoint if endpoint else "https://sts." + region + suffix
        trusted_identity_url(url, "assume_role", local_fixture)
        var result = Self(
            "assume_role",
            url,
            role_arn,
            session_name=session_name,
            ca_bundle=ca_bundle,
            local_fixture=local_fixture,
        )
        result._role_source = RoleSourceDescription(
            source.kind,
            source.endpoint,
            source.role_arn,
            source.token_file,
            source.session_name,
            source.authorization,
            source.ca_bundle,
            source.local_fixture,
            source.static_credentials.copy(),
            None,
        )
        result._sts_region = region
        result._external_id = external_id
        result._duration_seconds = duration_seconds
        return result^

    def _fetch_role(mut self) raises -> CredentialSnapshot:
        if not self._role_source:
            raise Error("AssumeRole source provider missing")
        validate_role_session(
            self.role_arn,
            self.session_name,
            self._external_id,
            self._duration_seconds,
        )
        var description = self._role_source.value().copy()
        if description.kind not in [
            "static",
            "web_identity",
            "container",
            "imds",
        ]:
            raise Error("Invalid or recursive AssumeRole source")
        var source = Self(
            description.kind,
            description.endpoint,
            description.role_arn,
            description.token_file,
            description.session_name,
            description.authorization,
            description.ca_bundle,
            description.local_fixture,
        )
        source.static_credentials = description.static_credentials.copy()
        var cache = CredentialCache(source)
        cache.snapshot = description.snapshot.copy()
        var credentials = cache.resolve()
        description.snapshot = cache.snapshot.copy()
        self._role_source = description^
        trusted_identity_url(self.endpoint, "assume_role", self.local_fixture)
        var form: List[Field] = [
            Field("Action", "AssumeRole"),
            Field("Version", "2011-06-15"),
            Field("RoleArn", self.role_arn),
            Field("RoleSessionName", self.session_name),
        ]
        if self._external_id:
            form.append(Field("ExternalId", self._external_id))
        if self._duration_seconds:
            form.append(
                Field("DurationSeconds", String(self._duration_seconds))
            )
        var body = bytes_of(canonical_query(form))
        var destination = identity_address(self.endpoint)
        var timestamp = utc_timestamp()
        var headers: List[Field] = [
            Field("host", destination.host),
            Field("content-type", "application/x-www-form-urlencoded"),
            Field("x-amz-date", timestamp),
        ]
        if credentials.session_token:
            headers.append(
                Field("x-amz-security-token", credentials.session_token)
            )
        var signature = sign(
            credentials,
            self._sts_region,
            "sts",
            "POST",
            destination.path,
            List[Field](),
            headers,
            sha256_hex(body),
            timestamp,
        )
        headers.append(Field("authorization", signature.authorization))
        var transport = CurlTransport(
            timeout_ms=5000,
            connect_timeout_ms=1000,
            max_response_bytes=65536,
            verify_tls=True,
            ca_bundle=self.ca_bundle,
        )
        var response = transport.send(
            HttpRequest("POST", destination.url, headers^, body^)
        )
        if response.status != 200:
            var code = "CredentialProviderFailure"
            var request_id = ""
            try:
                var nodes = parse_xml(
                    String(
                        from_utf8=Span(
                            unsafe_ptr=response.body.unsafe_ptr(),
                            length=len(response.body),
                        )
                    )
                )
                if nodes[0].name == "ErrorResponse":
                    request_id = child_text(nodes, 0, "RequestId")
                    for i in range(len(nodes)):
                        if nodes[i].parent == 0 and nodes[i].name == "Error":
                            code = child_text(nodes, i, "Code")
            except:
                pass
            self.last_error = S3Error(
                response.status,
                code,
                "AssumeRole credential exchange failed",
                request_id,
                "",
                "",
                "CredentialRefresh",
            )
            raise Error("AssumeRole credential exchange failed")
        return sts_snapshot(response_text(response), "AssumeRole")

    def fetch(mut self) raises -> CredentialSnapshot:
        self.last_error = None
        if self.kind == "static":
            validate_credentials(self.static_credentials)
            return CredentialSnapshot(
                self.static_credentials.copy(), 9223372036854775807
            )
        if self.kind == "assume_role":
            return self._fetch_role()
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
