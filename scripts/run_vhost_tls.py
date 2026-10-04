"""Optional isolated ZEROS3 TLS fixture; the SDK still uses standard S3 APIs."""
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time
import boto3

server_binary, executable = sys.argv[1:3]
with tempfile.TemporaryDirectory(prefix="mojo-vhost-tls-") as tmp:
    root = Path(tmp)
    cert = str(root / "cert.pem")
    key = str(root / "key.pem")
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
            cert,
            "-days",
            "1",
            "-subj",
            "/CN=localhost",
            "-addext",
            "subjectAltName=DNS:localhost,DNS:mojo-test.localhost",
        ],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        port = listener.getsockname()[1]
    endpoint = f'https://localhost:{port}'
    env = dict(
        os.environ,
        S3_ENDPOINT=endpoint,
        S3_ACCESS_KEY="mojo-tls-access",
        S3_SECRET_KEY="mojo-tls-secret",
        S3_SESSION_TOKEN="",
        S3_TEST_BUCKET="mojo-test",
        S3_CA_BUNDLE=cert,
        S3_FORCE_PATH_STYLE="false",
    )
    if not env.get("S3_STREAM_SOURCE"):
        subprocess.run(
            [
                sys.executable,
                str(Path(__file__).with_name("generate_transfer_fixture.py")),
                str(root / "source.bin"),
            ],
            check=True,
        )
        env["S3_STREAM_SOURCE"] = str(root / "source.bin")
    env["S3_STREAM_DESTINATION"] = str(root / "destination.bin")
    with (root / "server.log").open("wb") as log:
        server = subprocess.Popen(
            [
                server_binary,
                "serve",
                "-addr",
                f'127.0.0.1:{port}',
                "-store",
                str(root / "data"),
                "-access-key",
                env["S3_ACCESS_KEY"],
                "-secret-key",
                env["S3_SECRET_KEY"],
                "-tls-cert",
                cert,
                "-tls-key",
                key,
                "-vhost-base",
                "localhost",
            ],
            stdout=log,
            stderr=log,
        )
        try:
            for attempt in range(250):
                if server.poll() is not None:
                    raise RuntimeError("Local TLS server failed to start")
                try:
                    with socket.create_connection(
                        ("127.0.0.1", port), timeout=0.1
                    ):
                        break
                except OSError:
                    time.sleep(0.02)
            else:
                raise RuntimeError("Local TLS server startup timed out")
            client = boto3.client(
                "s3",
                endpoint_url=endpoint,
                aws_access_key_id=env["S3_ACCESS_KEY"],
                aws_secret_access_key=env["S3_SECRET_KEY"],
                region_name="us-east-1",
                verify=cert,
            )
            client.create_bucket(Bucket=env["S3_TEST_BUCKET"])
            subprocess.run([executable], env=env, check=True, timeout=120)
            assert not client.list_objects_v2(Bucket=env["S3_TEST_BUCKET"]).get(
                "Contents"
            )
            assert not client.list_multipart_uploads(
                Bucket=env["S3_TEST_BUCKET"]
            ).get("Uploads")
        finally:
            server.terminate()
            try:
                server.wait(timeout=5)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait()
