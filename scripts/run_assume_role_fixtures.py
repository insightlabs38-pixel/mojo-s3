"""Synthetic STS credentials and independent SigV4 checks; no AWS access."""
import datetime
import hashlib
import hmac
import http.server
import json
import os
import subprocess
import sys
import threading
import urllib.parse

state = {"assume": 0, "dynamic": 0, "source": 0}


def check_signature(handler, body, key, secret, token):
    authorization = handler.headers["Authorization"]
    fields = dict(
        p.strip().split("=", 1)
        for p in authorization.split(" ", 1)[1].split(",")
    )
    credential, scope = fields["Credential"].split("/", 1)
    assert credential == key
    date, region, service, terminal = scope.split("/")
    assert (region, service, terminal) == ("us-east-1", "sts", "aws4_request")
    names = fields["SignedHeaders"].split(";")
    headers = "".join(
        name + ":" + " ".join(handler.headers[name].split()) + "\n"
        for name in names
    )
    assert handler.headers["X-Amz-Security-Token"] == token
    canonical = (
        "POST\n"
        + handler.path
        + "\n\n"
        + headers
        + "\n"
        + fields["SignedHeaders"]
        + "\n"
        + hashlib.sha256(body).hexdigest()
    )
    text = (
        "AWS4-HMAC-SHA256\n"
        + handler.headers["X-Amz-Date"]
        + "\n"
        + scope
        + "\n"
        + hashlib.sha256(canonical.encode()).hexdigest()
    )
    signing = ("AWS4" + secret).encode()
    for part in [date, region, service, terminal]:
        signing = hmac.new(signing, part.encode(), hashlib.sha256).digest()
    assert (
        hmac.new(signing, text.encode(), hashlib.sha256).hexdigest()
        == fields["Signature"]
    )


class Handler(http.server.BaseHTTPRequestHandler):
    def reply(self, body, status=200):
        data = body.encode()
        self.send_response(status)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        assert self.path == "/source"
        state["source"] += 1
        expires = datetime.datetime.now(
            datetime.timezone.utc
        ) + datetime.timedelta(hours=1)
        self.reply(
            json.dumps(
                dict(
                    AccessKeyId=f'source-{state["source"]}',
                    SecretAccessKey="dynamic-secret",
                    Token=f'source-token-{state["source"]}',
                    Expiration=expires.strftime("%Y-%m-%dT%H:%M:%SZ"),
                )
            )
        )

    def do_POST(self):
        body = self.rfile.read(int(self.headers["Content-Length"]))
        form = urllib.parse.parse_qs(body.decode())
        assert form["Action"] == ["AssumeRole"]
        assert form["Version"] == ["2011-06-15"]
        assert form["RoleArn"] == ["arn:aws:iam::123456789012:role/fixture"]
        assert form["RoleSessionName"] == ["fixture-session"]
        name = self.path.strip("/")
        if name == "dynamic":
            check_signature(
                self,
                body,
                f'source-{state["source"]}',
                "dynamic-secret",
                f'source-token-{state["source"]}',
            )
        else:
            check_signature(
                self,
                body,
                "fixture-source",
                "fixture-source-secret",
                "fixture-source-token",
            )
        if name == "denied":
            return self.reply(
                "<ErrorResponse><Error><Code>AccessDenied</Code><Message>fixture</Message></Error><RequestId>fixture-request</RequestId></ErrorResponse>",
                403,
            )
        if name == "malformed":
            return self.reply("<AssumeRoleResponse/>")
        if name == "assume":
            assert form["ExternalId"] == ["fixture-external"] and form[
                "DurationSeconds"
            ] == ["900"]
            state[name] += 1
            key = f'assumed-key-{state[name]}'
        elif name == "dynamic":
            state[name] += 1
            key = f'dynamic-role-{state[name]}'
        else:
            key = "expired-key"
        expires = datetime.datetime.now(
            datetime.timezone.utc
        ) + datetime.timedelta(seconds=-1 if name == "expired" else 3600)
        self.reply(
            f'<AssumeRoleResponse><AssumeRoleResult><Credentials><AccessKeyId>{key}</AccessKeyId><SecretAccessKey>assumed-secret</SecretAccessKey><SessionToken>assumed-token</SessionToken><Expiration>{expires.strftime("%Y-%m-%dT%H:%M:%SZ")}</Expiration></Credentials></AssumeRoleResult></AssumeRoleResponse>'
        )

    def log_message(self, *args):
        pass


with http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        subprocess.run(
            [sys.argv[1]],
            check=True,
            timeout=30,
            env=dict(
                os.environ,
                S3_ROLE_ENDPOINT=f'http://127.0.0.1:{server.server_port}',
            ),
        )
        assert state == {"assume": 2, "dynamic": 2, "source": 2}
    finally:
        server.shutdown()
