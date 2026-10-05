"""Resolve native local credentials without network requests or secret output.

Run with S3/AWS environment keys or an AWS shared profile containing static keys.
"""
from mojo_s3.config import S3Config


def main() raises:
    var config = S3Config.from_default()
    print("S3 credential configuration resolved for region", config.region)
    print("Endpoint:", config.endpoint)
    # Pass config to S3Store(config). Do not print credentials or signed URLs.
