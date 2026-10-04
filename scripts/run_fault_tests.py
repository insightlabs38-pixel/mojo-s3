"""Start isolated deterministic HTTP fixtures and execute compiled Mojo tests."""
import http.server
import os
from pathlib import Path
import subprocess
import sys
import threading
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tests"))
from fault_server import Handler

with http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    endpoint = f'http://127.0.0.1:{server.server_port}'
    env = dict(
        os.environ, S3_FAULT_ENDPOINT=endpoint, HTTP_TEST_URL=endpoint + "/"
    )
    tmp = tempfile.TemporaryDirectory(prefix="mojo-concurrent-fixture-")
    source = Path(tmp.name) / "source.bin"
    with source.open("wb") as file:
        for _ in range(192):
            file.write(bytes(range(256)) * 256)
    env["S3_CONCURRENT_SOURCE"] = str(source)
    try:
        for executable in sys.argv[1:]:
            subprocess.run([executable], env=env, check=True, timeout=30)
    finally:
        server.shutdown()
        tmp.cleanup()
