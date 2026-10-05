"""Deterministic local workload identity fixtures, never real credentials."""
import datetime
import http.server
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time
import urllib.parse

state = {
    "credentials": 0,
    "objects": 0,
    "imds": 0,
    "sts": 0,
    "retry_credentials": 0,
    "retry_objects": 0,
}


def snapshot(expired=False):
    expires = datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(
        seconds=-1 if expired else 3600
    )
    return dict(
        AccessKeyId="fixture-key",
        SecretAccessKey="fixture-secret",
        Token=f'fixture-token-{state["credentials"]}',
        Expiration=expires.strftime("%Y-%m-%dT%H:%M:%SZ"),
        Code="Success",
    )


class Handler(http.server.BaseHTTPRequestHandler):
    def reply(self, body, status=200, retry_after=None):
        data = body.encode()
        self.send_response(status)
        self.send_header("Content-Length", str(len(data)))
        if retry_after is not None:
            self.send_header("Retry-After", str(retry_after))
        self.end_headers()
        try:
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def do_PUT(self):
        assert self.path == "/latest/api/token"
        assert self.headers["X-Aws-Ec2-Metadata-Token-Ttl-Seconds"] == "60"
        state["imds"] += 1
        self.reply("fixture-imds-token")

    def do_POST(self):
        form = urllib.parse.parse_qs(
            self.rfile.read(int(self.headers["Content-Length"])).decode()
        )
        assert form["Action"] == ["AssumeRoleWithWebIdentity"]
        assert form["WebIdentityToken"] == ["fixture-jwt"]
        state["sts"] += 1
        value = snapshot()
        self.reply(
            "<AssumeRoleWithWebIdentityResponse><AssumeRoleWithWebIdentityResult><Credentials><AccessKeyId>fixture-key</AccessKeyId><SecretAccessKey>fixture-secret</SecretAccessKey><SessionToken>fixture-token</SessionToken><Expiration>"
            + value["Expiration"]
            + "</Expiration></Credentials></AssumeRoleWithWebIdentityResult></AssumeRoleWithWebIdentityResponse>"
        )

    def do_GET(self):
        if self.path.startswith("/latest/meta-data/"):
            assert (
                self.headers["X-Aws-Ec2-Metadata-Token"] == "fixture-imds-token"
            )
            self.reply(
                "fixture-role" if self.path.endswith("/") else json.dumps(
                    snapshot()
                )
            )
        elif self.path == "/credentials":
            assert self.headers["Authorization"] == "fixture-auth"
            state["credentials"] += 1
            self.reply(json.dumps(snapshot()))
        elif self.path == "/denied":
            self.reply("denied", 403)
        elif self.path == "/retry-credentials":
            state["retry_credentials"] += 1
            value = snapshot()
            value["AccessKeyId"] = f'retry-key-{state["retry_credentials"]}'
            value["Token"] = f'retry-token-{state["retry_credentials"]}'
            self.reply(json.dumps(value))
        elif self.path.endswith("/expires-between-attempts"):
            state["retry_objects"] += 1
            attempt = state["retry_objects"]
            assert (
                self.headers["X-Amz-Security-Token"] == f'retry-token-{attempt}'
            )
            assert (
                f'Credential=retry-key-{attempt}/'
                in self.headers["Authorization"]
            )
            self.reply(
                "retry" if attempt == 1 else "ok",
                503 if attempt == 1 else 200,
                2 if attempt == 1 else None,
            )
        elif self.path == "/malformed":
            self.reply('{"AccessKeyId":"fixture"}')
        elif self.path == "/expired":
            self.reply(json.dumps(snapshot(True)))
        elif self.path == "/slow":
            time.sleep(5.5)
            self.reply(json.dumps(snapshot()))
        else:
            assert self.headers["X-Amz-Security-Token"].startswith(
                "fixture-token-"
            )
            assert "mojo-s3/" in self.headers["User-Agent"]
            state["objects"] += 1
            self.reply(
                "retry" if state["objects"] == 1 else "ok",
                503 if state["objects"] == 1 else 200,
            )

    def log_message(self, *args):
        pass


with tempfile.TemporaryDirectory(prefix="mojo-identity-") as tmp:
    token = Path(tmp) / "token"
    token.write_text("fixture-jwt")
    with http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
        threading.Thread(target=server.serve_forever, daemon=True).start()
        try:
            subprocess.run(
                [sys.argv[1]],
                check=True,
                timeout=30,
                env=dict(
                    os.environ,
                    S3_IDENTITY_ENDPOINT=f'http://127.0.0.1:{server.server_port}',
                    S3_IDENTITY_TOKEN_FILE=str(token),
                ),
            )
            assert state["sts"] == 1 and state["imds"] == 1
            assert state["credentials"] == 3 and state["objects"] == 2
            assert (
                state["retry_credentials"] == 2 and state["retry_objects"] == 2
            )
        finally:
            server.shutdown()
