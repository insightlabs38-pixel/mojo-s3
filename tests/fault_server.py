"""Test orchestration only: deterministic HTTP failures for the native client."""
import http.server
import socket
import threading
import time
import hashlib
import base64
from urllib.parse import urlsplit, parse_qs

counts = {}
lock = threading.Lock()
multipart = {}


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def reply(self, status, body=b"", headers=None):
        self.send_response(status)
        self.send_header("Content-Length", str(len(body)))
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def multipart_path(self):
        path = urlsplit(self.path).path
        return path if path.startswith("/bucket/concurrent-") else None

    def do_PUT(self):
        self.rfile.read(int(self.headers.get("Content-Length", 0)))
        path = self.multipart_path()
        if not path:
            return self.reply(501)
        number = int(parse_qs(urlsplit(self.path).query)["partNumber"][0])
        with lock:
            state = multipart[path]
            state["active"] += 1
            state["peak"] = max(state["peak"], state["active"])
        time.sleep(0.05)
        with lock:
            state["active"] -= 1
        if (
            path.endswith("fail")
            and not path.endswith("complete-fail")
            and number == 1
        ):
            return self.reply(503, b"<Error><Code>InternalError</Code></Error>")
        return self.reply(200, headers={"ETag": f'"part-{number}"'})

    def do_DELETE(self):
        path = self.multipart_path()
        if not path:
            return self.reply(501)
        with lock:
            state = multipart[path]
            state["abort"] += 1
            state["active_at_abort"] = state["active"]
        return self.reply(204)

    def do_GET(self):
        if self.path.endswith(
            ("/checksum-good", "/checksum-bad", "/checksum-composite")
        ):
            body = b"opaque content bytes"
            checksum = base64.b64encode(
                hashlib.sha256(
                    body if self.path.endswith("good") else b"wrong"
                ).digest()
            ).decode()
            headers = {
                "x-amz-checksum-sha256": checksum,
                "x-amz-checksum-type": "COMPOSITE" if self.path.endswith(
                    "composite"
                ) else "FULL_OBJECT",
            }
            return self.reply(200, body, headers)
        path = self.multipart_path()
        if path:
            with lock:
                state = multipart[path].copy()
            return self.reply(
                200,
                b"ok",
                {f"X-{k.replace('_','-')}": str(v) for k, v in state.items()},
            )
        with lock:
            counts[self.path] = counts.get(self.path, 0) + 1
            count = counts[self.path]
        if self.path.endswith("/slow"):
            time.sleep(0.15)
        if self.path.endswith("/reset") and count == 1:
            self.connection.shutdown(socket.SHUT_RDWR)
            self.connection.close()
            return
        if self.path.endswith("/retry") and count < 3:
            body = b"<Error><Code>SlowDown</Code><Message>retry fixture</Message></Error>"
            status = 503
        elif self.path.endswith("/denied"):
            body = b"<Error><Code>AccessDenied</Code></Error>"
            status = 403
        elif self.path.endswith("/redirect"):
            body = b"redirect"
            status = 302
        elif self.path.endswith("/overflow"):
            body = b"x" * 1024
            status = 200
        else:
            body = b"ok"
            status = 200
        self.send_response(status)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Attempts", str(count))
        self.send_header("X-Client-Port", str(self.client_address[1]))
        self.send_header("X-Request-Path", self.path)
        if status == 302:
            self.send_header("Location", "/bucket/followed")
        self.send_header("x-amz-request-id", str(count))
        if status == 503:
            self.send_header("Retry-After", "0")
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length", 0)))
        path = self.multipart_path()
        if path:
            query = parse_qs(urlsplit(self.path).query, keep_blank_values=True)
            if "uploads" in query:
                with lock:
                    multipart[path] = {
                        "active": 0,
                        "peak": 0,
                        "abort": 0,
                        "active_at_abort": -1,
                    }
                return self.reply(
                    200,
                    b"<InitiateMultipartUploadResult><UploadId>fixture</UploadId></InitiateMultipartUploadResult>",
                )
            return self.reply(200, b"<Error><Code>InternalError</Code></Error>")
        with lock:
            counts[self.path] = counts.get(self.path, 0) + 1
            count = counts[self.path]
        body = b"<Error><Code>InternalError</Code><Message>embedded failure</Message></Error>"
        self.send_response(200 if self.path.endswith("/complete") else 503)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Attempts", str(count))
        self.send_header("x-amz-request-id", str(count))
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=18081)
    args = parser.parse_args()
    http.server.ThreadingHTTPServer(
        ("127.0.0.1", args.port), Handler
    ).serve_forever()
