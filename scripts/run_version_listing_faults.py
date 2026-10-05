"""Independent query/response oracle with a two-state marker cycle."""
import http.server
import os
import subprocess
import sys
import threading
import urllib.parse

calls = {"cycle": 0, "limited": 0}


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        url = urllib.parse.urlsplit(self.path)
        bucket = url.path.strip("/")
        query = urllib.parse.parse_qs(url.query, keep_blank_values=True)
        assert query["encoding-type"] == ["url"]
        if bucket == "list-v2":
            assert query["list-type"] == ["2"]
            data = b"<ListBucketResult><EncodingType>url</EncodingType><IsTruncated>false</IsTruncated><Contents><Key>prefix/a+b%2Bc%252B</Key><Size>1</Size><ETag>opaque</ETag><LastModified>date</LastModified></Contents><CommonPrefixes><Prefix>prefix/a+b%2B/</Prefix></CommonPrefixes></ListBucketResult>"
            self.send_response(200)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        assert query["versions"] == [""]
        if bucket == "bucket":
            assert query["prefix"] == ["prefix/"]
            assert query["delimiter"] == ["/"]
            assert query["key-marker"] == ["prefix/雪 +"]
            assert query["version-id-marker"] == ["opaque%2F+/="]
            assert query["max-keys"] == ["2"]
            body = "<EncodingType>url</EncodingType><IsTruncated>false</IsTruncated><Version><Key>prefix%2Fa</Key><VersionId>opaque%2F+/=</VersionId><IsLatest>false</IsLatest><LastModified>date</LastModified><ETag>opaque</ETag><Size>7</Size></Version><DeleteMarker><Key>prefix%2Fb</Key><VersionId>null</VersionId><IsLatest>true</IsLatest><LastModified>date</LastModified></DeleteMarker>"
        else:
            calls[bucket] += 1
            marker = "b" if calls[bucket] == 2 else "a"
            body = f"<IsTruncated>true</IsTruncated><NextKeyMarker>{marker}</NextKeyMarker><NextVersionIdMarker>opaque</NextVersionIdMarker>"
        data = f"<ListVersionsResult><Name>{bucket}</Name>{body}</ListVersionsResult>".encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *args):
        pass


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
        ),
    )
    assert calls == {"cycle": 3, "limited": 1}, calls
    server.shutdown()
print("Independent version query and bounded pagination oracle passed")
