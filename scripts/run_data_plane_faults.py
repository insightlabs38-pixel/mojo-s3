"""Bounded isolated fixture for data-plane failures; synthetic credentials only."""
import http.server
import os
import subprocess
import sys
import threading


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def reply(self, body, status=200):
        payload = body.encode()
        self.send_response(status)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_PUT(self):
        self.rfile.read(int(self.headers.get("Content-Length", 0)))
        if self.path.endswith("copy-error"):
            self.reply("<Error><Code>SlowDown</Code></Error>")
        else:
            self.reply("<CopyObjectResult/>")

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        assert self.headers.get("Content-MD5")
        if b"omitted" in body:
            self.reply("<DeleteResult/>")
        else:
            self.reply(
                "<DeleteResult><Deleted><Key>good</Key></Deleted><Error><Key>denied</Key><Code>AccessDenied</Code></Error></DeleteResult>"
            )

    def do_GET(self):
        self.reply("", 304)

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
                S3_ENDPOINT=f'http://127.0.0.1:{server.server_port}',
                S3_REGION="us-east-1",
                S3_ACCESS_KEY="fixture",
                S3_SECRET_KEY="fixture",
                S3_SESSION_TOKEN="",
            ),
        )
    finally:
        server.shutdown()
