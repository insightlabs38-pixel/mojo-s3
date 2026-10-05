"""Native local credential providers. Resolution never mixes provider secrets."""
from std.io import FileHandle
from std.os import getenv
from std.os.path import exists
from mojo_s3.signing import Credentials


trait CredentialProvider(Movable):
    """Resolve credentials on demand; callers own the returned snapshot.

    Future refreshing providers can resolve on each call. S3Config currently
    captures one snapshot and does not refresh or share mutable provider state.
    """

    def resolve(mut self) raises -> Credentials:
        ...


def validate_credentials(credentials: Credentials) raises:
    if not credentials.access_key or not credentials.secret_key:
        raise Error("Credential provider requires both access and secret keys")
    for value in [
        credentials.access_key,
        credentials.secret_key,
        credentials.session_token,
    ]:
        for b in value.as_bytes():
            if b < 32 or b == 127:
                raise Error("Credential contains a control character")


struct StaticCredentials(Copyable, CredentialProvider):
    var credentials: Credentials

    def __init__(out self, credentials: Credentials) raises:
        validate_credentials(credentials)
        self.credentials = credentials.copy()

    def resolve(mut self) raises -> Credentials:
        return self.credentials.copy()


def environment_credentials(
    s3_access: String,
    s3_secret: String,
    s3_token: String,
    aws_access: String,
    aws_secret: String,
    aws_token: String,
) raises -> Optional[Credentials]:
    """Pure environment fixture entry point, with atomic S3/AWS precedence."""
    if s3_access or s3_secret or s3_token:
        var credentials = Credentials(s3_access, s3_secret, s3_token)
        validate_credentials(credentials)
        return Optional(credentials^)
    if aws_access or aws_secret or aws_token:
        var credentials = Credentials(aws_access, aws_secret, aws_token)
        validate_credentials(credentials)
        return Optional(credentials^)
    return None


struct EnvironmentCredentials(Copyable, CredentialProvider):
    def __init__(out self):
        pass

    def resolve(mut self) raises -> Credentials:
        var credentials = environment_credentials(
            getenv("S3_ACCESS_KEY"),
            getenv("S3_SECRET_KEY"),
            getenv("S3_SESSION_TOKEN"),
            getenv("AWS_ACCESS_KEY_ID"),
            getenv("AWS_SECRET_ACCESS_KEY"),
            getenv("AWS_SESSION_TOKEN"),
        )
        if not credentials:
            raise Error("No environment credentials configured")
        return credentials.value().copy()


def profile_value(
    text: String, profile: String, key: String, config_file: Bool = False
) raises -> String:
    """Read an AWS INI scalar; duplicate selected keys/sections fail closed.

    Unknown settings are ignored. Inline comments are not stripped from values
    because secrets may contain '#' or ';'. Nested settings are not interpreted.
    """
    if not profile or "\n" in profile or "\r" in profile:
        raise Error("Invalid AWS profile")
    var section = (
        "profile " + profile if config_file
        and profile != "default" else profile
    )
    var selected = False
    var section_seen = False
    var value_seen = False
    var result = String()
    for raw in text.split("\n"):
        var line = raw.strip()
        if not line or line.startswith("#") or line.startswith(";"):
            continue
        if line.startswith("["):
            if not line.endswith("]"):
                raise Error("Malformed AWS profile section")
            selected = (
                String(line[byte = 1 : line.byte_length() - 1]).strip()
                == section
            )
            if selected:
                if section_seen:
                    raise Error("Duplicate AWS profile section")
                section_seen = True
            continue
        if not selected:
            continue
        var pos = line.find("=")
        if pos < 0:
            raise Error("Malformed AWS profile setting")
        if String(line[byte=0:pos]).strip().lower() == key:
            if value_seen:
                raise Error("Duplicate AWS profile setting")
            value_seen = True
            result = String(String(line[byte = pos + 1 :]).strip())
    return result^


def profile_credentials(
    text: String, profile: String = "default", config_file: Bool = False
) raises -> Optional[Credentials]:
    var access = profile_value(text, profile, "aws_access_key_id", config_file)
    var secret = profile_value(
        text, profile, "aws_secret_access_key", config_file
    )
    var token = profile_value(text, profile, "aws_session_token", config_file)
    if not access and not secret and not token:
        return None
    var credentials = Credentials(access, secret, token)
    validate_credentials(credentials)
    return Optional(credentials^)


def read_profile_file(path: String, required: Bool = False) raises -> String:
    if not path or not exists(path):
        if required:
            raise Error("Configured AWS profile file does not exist")
        return ""
    var file = FileHandle(path, "r")
    var text = file.read(1024 * 1024 + 1)
    if text.byte_length() > 1024 * 1024:
        raise Error("AWS profile file exceeds 1 MiB limit")
    return text^


struct SharedFileCredentials(Copyable, CredentialProvider):
    var path: String
    var profile: String
    var config_file: Bool

    def __init__(
        out self,
        path: String,
        profile: String = "default",
        config_file: Bool = False,
    ):
        self.path = path
        self.profile = profile
        self.config_file = config_file

    def resolve(mut self) raises -> Credentials:
        var credentials = profile_credentials(
            read_profile_file(self.path, True), self.profile, self.config_file
        )
        if not credentials:
            raise Error("AWS profile has no supported static credentials")
        return credentials.value().copy()


def aws_profile() -> String:
    return getenv("AWS_PROFILE", getenv("AWS_DEFAULT_PROFILE", "default"))


def shared_file_path(config_file: Bool = False) -> String:
    var explicit_path = getenv(
        "AWS_CONFIG_FILE" if config_file else "AWS_SHARED_CREDENTIALS_FILE"
    )
    if explicit_path:
        return explicit_path^
    var home = getenv("HOME")
    if not home:
        return ""
    return home + ("/.aws/config" if config_file else "/.aws/credentials")


def default_credentials() raises -> Credentials:
    var credentials = environment_credentials(
        getenv("S3_ACCESS_KEY"),
        getenv("S3_SECRET_KEY"),
        getenv("S3_SESSION_TOKEN"),
        getenv("AWS_ACCESS_KEY_ID"),
        getenv("AWS_SECRET_ACCESS_KEY"),
        getenv("AWS_SESSION_TOKEN"),
    )
    if credentials:
        return credentials.value().copy()
    var profile = aws_profile()
    credentials = profile_credentials(
        read_profile_file(
            shared_file_path(), Bool(getenv("AWS_SHARED_CREDENTIALS_FILE"))
        ),
        profile,
    )
    if credentials:
        return credentials.value().copy()
    credentials = profile_credentials(
        read_profile_file(
            shared_file_path(True), Bool(getenv("AWS_CONFIG_FILE"))
        ),
        profile,
        True,
    )
    if credentials:
        return credentials.value().copy()
    raise Error(
        "No supported credentials found in environment or AWS profile files"
    )
