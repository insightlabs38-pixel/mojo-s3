# Credentials and AWS configuration

Credential providers run in native Mojo without Python or network calls. Existing
`mojo_s3.signing.Credentials(access_key, secret_key, session_token)` remains the
signing value type. Use an empty string when no session token is needed.

```mojo
from mojo_s3.credentials import StaticCredentials
from mojo_s3.signing import Credentials
from mojo_s3.config import S3Config

var provider = StaticCredentials(Credentials("access", "secret", ""))
var config = S3Config.aws(provider.resolve(), "eu-west-1")
```

For real applications, load secrets from environment or files instead of source:

```mojo
from mojo_s3.config import S3Config

var config = S3Config.from_default()
```

`from_default()` resolves a credential snapshot in this order:

1. `S3_ACCESS_KEY`, `S3_SECRET_KEY`, optional `S3_SESSION_TOKEN`.
2. `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, optional `AWS_SESSION_TOKEN`.
3. Selected profile in the AWS shared credentials file.
4. Selected profile in the AWS shared config file.

If any key or token from an environment group is nonempty, that whole group is
selected. Both keys are required. A partial higher priority provider raises an
error rather than combining keys/tokens from another provider or silently falling
back. The same rule applies to file profiles with partial static credentials.
Missing static credentials in a profile allow the next file provider. Secrets are
never included in provider error messages. Credential control characters are
rejected.

`S3Config.from_env()` uses only the environment groups and fails when neither
contains complete credentials. `EnvironmentCredentials.resolve()` exposes the
same behavior. `SharedFileCredentials(path, profile="default", config_file=False)`
loads one explicit file. `StaticCredentials.resolve()` returns a copy of its
validated value. All implement `CredentialProvider.resolve(mut self)`.

## Files and profiles

Paths default to `$HOME/.aws/credentials` and `$HOME/.aws/config`. Override them
with `AWS_SHARED_CREDENTIALS_FILE` and `AWS_CONFIG_FILE`. An explicitly configured
missing file is an error; a missing default file is skipped. Paths are used
literally (no shell expansion). Each file read is limited to 1 MiB.

Profile selection uses `AWS_PROFILE`, then `AWS_DEFAULT_PROFILE`, then `default`.
Credentials-file sections use `[name]`; config-file sections use `[profile name]`
and `[default]`. Supported settings are `aws_access_key_id`,
`aws_secret_access_key`, `aws_session_token`, and config-file `region`. For example:

```ini
# ~/.aws/credentials
[ci]
aws_access_key_id = example-access
aws_secret_access_key = example-secret
aws_session_token = example-session-token
```

```ini
# ~/.aws/config
[profile ci]
region = eu-west-1
```

Blank lines and whole-line `#`/`;` comments are supported. Values are trimmed, but
inline comments are not removed because these characters may be part of a secret.
Duplicate selected sections or selected credential/region keys, malformed section
headers, and malformed selected settings fail closed. Unknown settings are ignored.
This is a scalar static-profile reader, not a complete AWS SDK config interpreter.

## Region and endpoints

Region precedence is `S3_REGION`, `AWS_REGION`, `AWS_DEFAULT_REGION`, selected
config-file `region` (only in `from_default()`), then `us-east-1`.
`S3Config.aws(credentials, region)` and environment/default factories choose the
regional HTTPS AWS S3 endpoint; `cn-*` regions use `amazonaws.com.cn`.
Other AWS sovereign partitions, FIPS, dualstack and access points are not inferred;
configure those endpoints explicitly.

`S3_ENDPOINT` overrides the generated endpoint. An explicit endpoint defaults to
path-style addressing. Generated AWS endpoints default to virtual-host addressing.
`S3_FORCE_PATH_STYLE=true` or `false` overrides this choice; other values fail.
Direct `S3Config(endpoint, region, credentials, ...)` continues to support generic
S3-compatible endpoints with explicit addressing configuration.

## Lifetime and unsupported providers

Providers return owned credential snapshots. The static default chain retains that
snapshot. Explicit experimental workload providers use an owned expiration-aware
CredentialCache and refresh before signing; they never reuse expired credentials
when refresh fails.
`CredentialProvider` is the static provider extension contract; it does not
provide automatic expiration semantics. Refreshing CredentialSource and caches
are a separate experimental interface. Construct a new configuration/store when rotating credentials;
never mutate a store concurrently.

ECS, EC2 IMDS, web identity, AssumeRole/STS, SSO, `credential_process`, role chaining
remain outside the static default chain. Native opt-in Web Identity/container/IMDSv2
providers and refresh semantics are now experimental; see [PHASE2.md](PHASE2.md). A profile containing only these
settings cannot resolve credentials. Session-token signing is supported when keys
and a token are provided by a supported source.

Keep profile files private (normally mode `0600`), avoid committing credentials,
and never print Authorization headers or presigned URLs. The executable example
`examples/credentials.mojo` resolves configuration and prints no secrets.


## Experimental signed AssumeRole

`CredentialSource.assume_role(source, role_arn, session_name="mojo-s3",
region="us-east-1", external_id="", duration_seconds=0, ...)` accepts an owned
static, Web Identity, container, or IMDSv2 source. It independently refreshes source
credentials before signing a bounded native STS POST, then caches expiring role
credentials. The default endpoint is regional HTTPS with TLS verification; a
custom CA is optional. Explicit loopback fixture HTTP is test-only. Requests use
service `sts`, SigV4 and session tokens without exposing credentials in diagnostics.
Duration 0 omits the parameter; explicit values are 900..43200 and remain subject
to the role's service-side maximum. Session and external ID syntax are checked;
AWS validates role ARN existence, account/policy and full semantic constraints.

Role chaining and cycles are rejected rather than recursively resolving profiles.
SSO, credential_process and source_profile role configuration remain unsupported.
Programmatic static role sources use CredentialSource.static(Credentials(...));
no remote provider is added to the static environment/default chain. Each store
and cache has one active owner; parallel workers get independent owned copies.
Structured STS HTTP errors use category CredentialRefresh and retain status/code/
request ID. Credential refresh failure prevents signing the S3 request. Never log
Authorization, tokens, secret keys or persisted provider state.
