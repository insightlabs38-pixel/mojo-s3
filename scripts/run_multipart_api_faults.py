"""Independent malformed-listing and stateful server-side copy oracle."""
import http.server
import os
import subprocess
import sys
import threading
import urllib.parse

aborted = []
copy_requests = []
wide_ranges = []


class Handler(http.server.BaseHTTPRequestHandler):
    def reply(self, text, status=200):
        data = text.encode()
        self.send_response(status)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("ETag", '"source"')
        self.end_headers()
        self.wfile.write(data)

    def do_HEAD(self):
        self.send_response(200)
        self.send_header(
            "Content-Length",
            str(
                5 * 1024**3
                + 7 if self.path.endswith("wide-source") else 6 * 1024**2
            ),
        )
        self.send_header("ETag", '"source"')
        self.end_headers()

    def do_GET(self):
        path = urllib.parse.urlsplit(self.path)
        mode = path.path.split("/")[-1]
        query = urllib.parse.parse_qs(path.query, keep_blank_values=True)
        if "tagging" in query:
            tag = "<Tag><Key>a</Key><Value>b</Value></Tag>"
            tags = tag * (
                2 if mode == "duplicate" else 11 if mode == "oversized" else 0
            )
            body = (
                "<Tagging>"
                + ("<TagSet>" + tags + "</TagSet>" if mode != "missing" else "")
                + "</Tagging>"
            )
        elif "uploadId" in query:
            part = "<Part><PartNumber>1</PartNumber><ETag>opaque</ETag><Size>7</Size></Part>"
            if mode == "negative":
                part = part.replace("<Size>7", "<Size>-1")
            if mode == "part-size":
                part = part.replace("<Size>7", "<Size>5368709121")
            if mode == "overflow":
                part = part.replace("<Size>7", "<Size>9223372036854775808")
            if mode == "oversized":
                part += part.replace("<PartNumber>1", "<PartNumber>2")
            if mode == "duplicate":
                part *= 2
            identity = "wrong" if mode == "identity" else "opaque+/id="
            truncated = (
                "yes" if mode
                == "boolean" else "true" if mode
                == "marker" else "false"
            )
            body = f"<ListPartsResult><UploadId>{identity}</UploadId>{part}<IsTruncated>{truncated}</IsTruncated><NextPartNumberMarker>0</NextPartNumberMarker></ListPartsResult>"
        else:
            mode = path.path.strip("/")
            key = "other/key" if mode == "outside" else "prefix/key"
            upload = (
                f"<Upload><Key>{key}</Key><UploadId>opaque</UploadId></Upload>"
            )
            if mode in ["oversized", "duplicate"]:
                upload += upload if mode == "duplicate" else upload.replace(
                    "opaque", "second"
                )
            body = (
                "<ListMultipartUploadsResult>"
                + upload
                + "<IsTruncated>"
                + ("true" if mode == "marker" else "false")
                + "</IsTruncated><NextKeyMarker>prefix/a</NextKeyMarker><NextUploadIdMarker>old</NextUploadIdMarker></ListMultipartUploadsResult>"
            )
        self.reply(body)

    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length", "0")))
        if "uploads" in self.path:
            self.reply(
                "<InitiateMultipartUploadResult><UploadId>opaque</UploadId></InitiateMultipartUploadResult>"
            )
        elif urllib.parse.urlsplit(self.path).path.endswith("wide-copy"):
            self.reply(
                "<CompleteMultipartUploadResult><ETag>wide-result</ETag></CompleteMultipartUploadResult>"
            )
        else:
            self.reply(
                "<Error><Code>SlowDown</Code><RequestId>primary</RequestId></Error>"
            )

    def do_PUT(self):
        assert (
            int(self.headers.get("Content-Length", "0")) == 0
        ), "server-side copy must send no source payload"
        assert self.headers["x-amz-copy-source-if-match"] == '"source"'
        mode = urllib.parse.urlsplit(self.path).path.split("/")[-1]
        if mode == "wide-copy":
            number = int(
                urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query)[
                    "partNumber"
                ][0]
            )
            expected = (
                "bytes=0-5368709119" if number
                == 1 else "bytes=5368709120-5368709126"
            )
            assert self.headers["x-amz-copy-source-range"] == expected
            wide_ranges.append(expected)
            self.reply(
                "<CopyPartResult><ETag>wide-part</ETag></CopyPartResult>"
            )
            return
        assert self.headers["x-amz-copy-source-range"] == "bytes=0-6291455"
        copy_requests.append(mode)
        self.reply(
            "<CopyPartResult><ETag>part</ETag></CopyPartResult>" if mode
            == "complete-error" else "<Error><Code>SlowDown</Code></Error>"
        )

    def do_DELETE(self):
        mode = urllib.parse.urlsplit(self.path).path.split("/")[-1]
        aborted.append(mode)
        self.reply(
            "<Error><Code>AccessDenied</Code></Error>" if mode
            == "abort-error" else "",
            403 if mode == "abort-error" else 204,
        )

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
    assert sorted(aborted) == ["abort-error", "complete-error", "part-error"]
    assert sorted(copy_requests) == sorted(aborted)
    assert wide_ranges == ["bytes=0-5368709119", "bytes=5368709120-5368709126"]
    server.shutdown()
print(
    "Copy cleanup and zero-payload oracle passed; intentional abort failure retains explicit orphan"
)
