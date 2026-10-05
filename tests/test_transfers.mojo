from std.testing import assert_true
from mojo_s3.transfers import TransferOptions


def main() raises:
    var options = TransferOptions()
    assert_true(not options.uses_multipart(0))
    assert_true(not options.uses_multipart(64 * 1024 * 1024 - 1))
    assert_true(options.uses_multipart(64 * 1024 * 1024))
    assert_true(not TransferOptions(multipart_threshold=0).uses_multipart(0))
    assert_true(TransferOptions(multipart_threshold=0).uses_multipart(1))
    for bad in [
        TransferOptions(multipart_threshold=-1),
        TransferOptions(workers=0),
        TransferOptions(workers=17),
        TransferOptions(part_size=1),
        TransferOptions(part_size=65 * 1024 * 1024),
        TransferOptions(workers=8, max_in_flight_bytes=32 * 1024 * 1024),
    ]:
        var failed = False
        try:
            bad.validate()
        except:
            failed = True
        assert_true(failed)
    print("Transfer threshold, zero-file and bounded-buffer policies passed")
