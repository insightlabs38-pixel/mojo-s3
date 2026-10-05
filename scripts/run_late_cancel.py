"""Server commits before delayed success; cancellation cannot imply rollback."""
import http.server
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time
import urllib.parse

parts = set()
committed = False
aborts = 0


class Handler(http.server.BaseHTTPRequestHandler):
    def reply(self, text):
        data = text.encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("ETag", '"part"')
        self.end_headers()
        self.wfile.write(data)

    def do_PUT(self):
        remaining = int(self.headers["Content-Length"])
        while remaining:
            data = self.rfile.read(min(65536, remaining))
            assert data
            remaining -= len(data)
        parts.add(
            int(
                urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query)[
                    "partNumber"
                ][0]
            )
        )
        self.reply("")

    def do_POST(self):
        global committed
        self.rfile.read(int(self.headers.get("Content-Length", "0")))
        if "uploads" in self.path:
            self.reply(
                "<InitiateMultipartUploadResult><UploadId>late-id</UploadId></InitiateMultipartUploadResult>"
            )
        else:
            assert parts == {1, 2}
            committed = True
            signal.touch()
            time.sleep(0.1)
            self.reply(
                "<CompleteMultipartUploadResult><ETag>committed</ETag></CompleteMultipartUploadResult>"
            )

    def do_DELETE(self):
        global aborts
        aborts += 1
        self.reply("")

    def log_message(self, *args):
        pass


with tempfile.TemporaryDirectory(prefix="mojo-late-cancel-") as tmp:
    signal = Path(tmp) / "committed"
    source = Path(tmp) / "source"
    with source.open("wb") as handle:
        handle.truncate(5 * 1024**2 + 7)
    with http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
        threading.Thread(target=server.serve_forever, daemon=True).start()
        subprocess.run(
            [sys.argv[1]],
            check=True,
            timeout=60,
            env=dict(
                os.environ,
                S3_ENDPOINT=f"http://127.0.0.1:{server.server_port}",
                S3_REGION="us-east-1",
                S3_ACCESS_KEY="fixture",
                S3_SECRET_KEY="fixture",
                S3_SESSION_TOKEN="",
                S3_STREAM_SOURCE=str(source),
                S3_COMMIT_SIGNAL=str(signal),
            ),
        )
        assert committed and aborts == 0
        server.shutdown()
