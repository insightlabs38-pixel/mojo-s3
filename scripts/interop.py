"""Optional boto3 interoperability verification. Never imported by SDK code."""
import hashlib
import os
import subprocess
import sys
import uuid
from pathlib import Path
import boto3
from botocore.config import Config

client = boto3.client(
    "s3",
    endpoint_url=os.environ["S3_ENDPOINT"],
    region_name=os.environ.get("S3_REGION", "us-east-1"),
    aws_access_key_id=os.environ["S3_ACCESS_KEY"],
    aws_secret_access_key=os.environ["S3_SECRET_KEY"],
    aws_session_token=os.environ.get("S3_SESSION_TOKEN"),
    config=Config(s3={"addressing_style": "path"}),
)
bucket = os.environ["S3_TEST_BUCKET"]
prefix = "mojo-interop-" + uuid.uuid4().hex + "/"
source = Path(os.environ["S3_STREAM_SOURCE"])
try:
    client.upload_file(str(source), bucket, prefix + "reference")
    subprocess.run(
        [sys.argv[1]],
        env=dict(os.environ, S3_INTEROP_PREFIX=prefix),
        check=True,
        timeout=120,
    )
    response = client.get_object(Bucket=bucket, Key=prefix + "mojo")
    sha = hashlib.sha256()
    with response["Body"] as body:
        for chunk in iter(lambda: body.read(65536), b""):
            sha.update(chunk)
    expected = hashlib.sha256()
    with source.open("rb") as file:
        for chunk in iter(lambda: file.read(65536), b""):
            expected.update(chunk)
    assert sha.digest() == expected.digest()
    print(
        "native Mojo upload verified by boto3; bidirectional SHA256 interoperability passed"
    )
finally:
    for key in ["reference", "mojo"]:
        client.delete_object(Bucket=bucket, Key=prefix + key)
