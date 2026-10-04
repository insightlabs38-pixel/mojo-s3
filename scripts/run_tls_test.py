"""Ephemeral local TLS verification fixture; openssl is test orchestration only."""
import http.server
import os
from pathlib import Path
import ssl
import subprocess
import sys
import tempfile
import threading


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Length", "2")
        self.end_headers()
        self.wfile.write(b"ok")

    def log_message(self, *args):
        pass


with tempfile.TemporaryDirectory(prefix="mojo-tls-") as tmp:
    ca = str(Path(tmp) / "ca.pem")
    key = str(Path(tmp) / "key.pem")
    subprocess.run(
        [
            "openssl",
            "req",
            "-x509",
            "-newkey",
            "rsa:2048",
            "-nodes",
            "-keyout",
            key,
            "-out",
            ca,
            "-days",
            "1",
            "-subj",
            "/CN=localhost",
            "-addext",
            "subjectAltName=DNS:localhost",
        ],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(ca, key)
    with http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
        server.socket = context.wrap_socket(server.socket, server_side=True)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        try:
            subprocess.run(
                [sys.argv[1]],
                check=True,
                timeout=30,
                env=dict(
                    os.environ,
                    S3_TLS_ENDPOINT=f'https://localhost:{server.server_port}/',
                    S3_TLS_CA=ca,
                ),
            )
        finally:
            server.shutdown()
