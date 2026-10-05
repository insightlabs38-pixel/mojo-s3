"""Stream a sparse fixture through a bounded wire oracle, without storing parts.

Default: 128 MiB + 7 bytes. --wide: 5 GiB + 7 bytes, testing the maximal
part length and the following 64-bit offset. Neither mode proves AWS throughput.
"""
import hashlib
import http.server
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time
import urllib.parse
import xml.etree.ElementTree as ET

part_size = (5 * 1024**3) if "--wide" in sys.argv[2:] else (128 * 1024**2)
size = part_size + 7
sentinels = {
    0: b"start!",
    part_size // 2: b"middle",
    part_size - 6: b"border",
    part_size: b"last007",
}
parts = {}
errors = []
lock = threading.Lock()
completed = False


class Handler(http.server.BaseHTTPRequestHandler):
    def reply(self, text):
        data = text.encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("ETag", '"fixture-part"')
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        global completed
        if "uploads" in self.path:
            self.reply(
                "<InitiateMultipartUploadResult><UploadId>opaque+/id=</UploadId></InitiateMultipartUploadResult>"
            )
        else:
            data = self.rfile.read(int(self.headers["Content-Length"]))
            root = ET.fromstring(data)
            with lock:
                assert sorted(parts) == [1, 2]
            assert [int(n.text) for n in root.findall("./Part/PartNumber")] == [
                1,
                2,
            ]
            completed = True
            self.reply(
                "<CompleteMultipartUploadResult><ETag>fixture-complete</ETag></CompleteMultipartUploadResult>"
            )

    def do_PUT(self):
        try:
            query = urllib.parse.parse_qs(
                urllib.parse.urlsplit(self.path).query
            )
            assert query["uploadId"] == ["opaque+/id="]
            number = int(query["partNumber"][0])
            offset = (number - 1) * part_size
            expected = min(part_size, size - offset)
            assert int(self.headers["Content-Length"]) == expected
            digest = hashlib.sha256()
            received = 0
            while received < expected:
                chunk = self.rfile.read(min(65536, expected - received))
                assert chunk, "premature upload EOF"
                for position, value in sentinels.items():
                    relative = position - offset - received
                    if 0 <= relative < len(chunk):
                        assert chunk[relative : relative + len(value)] == value
                digest.update(chunk)
                received += len(chunk)
            assert digest.hexdigest() == self.headers["x-amz-content-sha256"]
            with lock:
                assert number not in parts
                parts[number] = received
            self.reply("")
        except Exception as error:
            errors.append(repr(error))
            self.close_connection = True

    def log_message(self, *args):
        pass


with tempfile.TemporaryDirectory(prefix="mojo-large-stream-") as tmp:
    source = Path(tmp) / "sparse"
    with source.open("wb") as fixture:
        fixture.truncate(size)
        for position, value in sentinels.items():
            fixture.seek(position)
            fixture.write(value)
    with http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
        threading.Thread(target=server.serve_forever, daemon=True).start()
        env = dict(
            os.environ,
            S3_ENDPOINT=f"http://127.0.0.1:{server.server_port}",
            S3_REGION="us-east-1",
            S3_ACCESS_KEY="fixture",
            S3_SECRET_KEY="fixture",
            S3_SESSION_TOKEN="",
            S3_STREAM_SOURCE=str(source),
            S3_PART_BYTES=str(part_size),
        )
        begin = time.monotonic()
        process = subprocess.Popen([sys.argv[1]], env=env)
        peak_kib = 0
        while process.poll() is None:
            try:
                for line in (
                    Path(f"/proc/{process.pid}/status").read_text().splitlines()
                ):
                    if line.startswith("VmRSS:"):
                        peak_kib = max(peak_kib, int(line.split()[1]))
            except FileNotFoundError:
                pass
            if time.monotonic() - begin > 180:
                process.kill()
                raise AssertionError("wire test timeout")
            time.sleep(0.01)
        server.shutdown()
        assert process.returncode == 0, errors
        assert not errors and completed and sum(parts.values()) == size
        # Conservative ordinary-runtime ceiling; sanitizers may reserve more.
        if os.environ.get("S3_CHECK_STREAM_RSS", "1") == "1":
            assert (
                peak_kib < 128 * 1024
            ), f"unbounded part allocation: {peak_kib} KiB"
        print(
            f"wire bytes={size} parts={parts} peak_native_rss_kib={peak_kib} elapsed_seconds={time.monotonic()-begin:.3f}"
        )
