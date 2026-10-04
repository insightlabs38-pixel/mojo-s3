"""Local MinIO STS interoperability fixture; never a runtime credential provider."""
import os
import subprocess
import sys
from urllib.parse import urlsplit
import boto3

endpoint = os.environ["S3_ENDPOINT"]
if urlsplit(endpoint).hostname not in {"127.0.0.1", "localhost"}:
    raise SystemExit("This STS fixture is restricted to local test servers")
client = boto3.client(
    "sts",
    endpoint_url=endpoint,
    region_name=os.environ.get("S3_REGION", "us-east-1"),
    aws_access_key_id=os.environ["S3_ACCESS_KEY"],
    aws_secret_access_key=os.environ["S3_SECRET_KEY"],
)
credentials = client.assume_role(
    RoleArn="arn:aws:iam::123456789012:role/test",
    RoleSessionName="mojo-native-fixture",
    DurationSeconds=900,
)["Credentials"]
env = dict(
    os.environ,
    S3_ACCESS_KEY=credentials["AccessKeyId"],
    S3_SECRET_KEY=credentials["SecretAccessKey"],
    S3_SESSION_TOKEN=credentials["SessionToken"],
)
for executable in sys.argv[1:]:
    subprocess.run([executable], env=env, check=True, timeout=120)
print(
    "Native S3 contract passed using live local MinIO STS session credentials"
)
