"""Concurrent range faults, out-of-order responses and staging cleanup."""
import base64
import hashlib
import http.server
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time

payload = bytes(i % 251 for i in range(7169))
lock = threading.Lock()
active = 0


class Handler(http.server.BaseHTTPRequestHandler):
    def reply(self, data, status, start=0, end=0, headers=True):
        self.send_response(status)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("ETag", '"fixture"')
        if headers:
            self.send_header(
                "Content-Range", f'bytes {start}-{end}/{len(payload)}'
            )
        self.end_headers()
        try:
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def do_HEAD(self):
        self.send_response(200)
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("ETag", '"fixture"')
        digest = hashlib.sha256(
            b"wrong" if self.path.endswith("checksum") else payload
        ).digest()
        self.send_header(
            "x-amz-checksum-sha256", base64.b64encode(digest).decode()
        )
        self.send_header("x-amz-checksum-type", "FULL_OBJECT")
        self.end_headers()

    def do_GET(self):
        global active
        with lock:
            active += 1
        try:
            start, end = map(int, self.headers["Range"][6:].split("-"))
            assert self.headers["If-Match"] == '"fixture"'
            time.sleep(0.015 if start % 2048 == 0 else 0.003)
            data = payload[start : end + 1]
            if self.path.endswith("denied") and start == 1024:
                self.reply(
                    b"<Error><Code>AccessDenied</Code></Error>",
                    403,
                    headers=False,
                )
            elif self.path.endswith("range"):
                self.reply(data, 206, start + 1, end + 1)
            elif self.path.endswith("truncated"):
                self.reply(data[:-1], 206, start, end)
            else:
                self.reply(data, 206, start, end)
        finally:
            with lock:
                active -= 1

    def log_message(self, *args):
        pass


with tempfile.TemporaryDirectory(prefix="mojo-download-fault-") as tmp:
    destination = Path(tmp) / "existing"
    destination.write_bytes(b"original contents")
    with http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
        threading.Thread(target=server.serve_forever, daemon=True).start()
        try:
            subprocess.run(
                [sys.argv[1]],
                check=True,
                timeout=60,
                env=dict(
                    os.environ,
                    S3_ENDPOINT=f'http://127.0.0.1:{server.server_port}',
                    S3_REGION="us-east-1",
                    S3_ACCESS_KEY="fixture",
                    S3_SECRET_KEY="fixture",
                    S3_SESSION_TOKEN="",
                    S3_DOWNLOAD_DESTINATION=str(destination),
                ),
            )
            assert (
                active == 0
            ), "workers must finish before native executable returns"
            assert destination.read_bytes() == b"original contents"
            assert (Path(tmp) / "existing-success").read_bytes() == payload
            assert sorted(p.name for p in Path(tmp).iterdir()) == [
                "existing",
                "existing-success",
            ]
        finally:
            server.shutdown()
