"""Consumer compilation through the root facade, without internal imports."""
from std.collections import List
from std.testing import assert_equal, assert_true
from mojo_s3 import (
    S3Store,
    S3Config,
    Credentials,
    Field,
    PutOptions,
    ReadOptions,
    CopyOptions,
    ObjectRange,
    ObjectIdentifier,
    Conditions,
    TransferManager,
    TransferOptions,
    TransferControl,
    TransferProgress,
    ProgressObserver,
    MultipartPlan,
    plan_multipart,
    UploadedPart,
    PartsPage,
    MultipartUpload,
    MultipartUploadsPage,
    PartsPaginator,
    MultipartUploadsPaginator,
    CredentialSource,
    CredentialCache,
    CredentialSnapshot,
)


struct ConsumerObserver(ProgressObserver):
    var requested: Bool

    def __init__(out self):
        self.requested = False

    def on_progress(mut self, progress: TransferProgress):
        self.requested = progress.completed_bytes == progress.total_bytes

    def cancel_requested(self) -> Bool:
        return self.requested


def main() raises:
    assert_equal(ObjectIdentifier("key").version_id, "")
    var copy = CopyOptions(tagging_directive="REPLACE")
    assert_equal(copy.tagging_directive, "REPLACE")
    var plan: MultipartPlan = plan_multipart(5 * 1024 * 1024 + 1)
    assert_equal(plan.part_count, 1)
    var parts = PartsPage(List[UploadedPart](), False, 0)
    var uploads = MultipartUploadsPage(List[MultipartUpload](), False, "", "")
    assert_true(not parts.truncated and not uploads.truncated)
    var pp = PartsPaginator("bucket", "key", "opaque", 2)
    var up = MultipartUploadsPaginator("bucket", "prefix/", 2)
    assert_equal(pp.marker, 0)
    assert_equal(up.pages_loaded, 0)
    var source = CredentialSource.static(Credentials("fixture", "secret", ""))
    var role = CredentialSource.assume_role(
        source, "arn:aws:iam::123456789012:role/fixture"
    )
    var cache = CredentialCache(role)
    var manager = TransferManager(
        S3Store(
            S3Config(
                "https://s3.example.com",
                "us-east-1",
                Credentials("fixture", "secret", ""),
            )
        ),
        TransferOptions(),
    )
    assert_true(not manager.options.uses_multipart(0))
    var observer = ConsumerObserver()
    observer.on_progress(TransferProgress(7, 7, 1, False))
    assert_true(observer.cancel_requested())
    var control = TransferControl()
    control.cancel()
    assert_true(control.is_cancelled())
    _ = cache
    print(
        "Root public facade consumer and safe observer cancellation compile/run passed"
    )
