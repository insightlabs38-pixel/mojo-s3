from std.atomic import Atomic
from std.collections import List
from std.ffi import external_call
from std.memory import Pointer
from std.testing import assert_equal
from mojo_s3.crypto import hash_text

comptime Raw = Pointer[UInt8, MutUntrackedOrigin]


@fieldwise_init
struct Job(Movable):
    var counter: Pointer[Atomic[Int32], MutUntrackedOrigin]
    var done: Int


def worker(raw: Raw) abi("C") -> Optional[Raw]:
    var job = raw.unsafe_bitcast[Job]()
    try:
        for _ in range(100):
            _ = hash_text("native thread")
            _ = job[].counter[].fetch_add(1)
        raise Error("caught on worker")
    except:
        job[].done = 1
    return None


def main() raises:
    var counter = Atomic[Int32](0)
    var jobs = List[Job](capacity=8)
    var ids = List[UInt](length=8, fill=0)
    for _ in range(8):
        jobs.append(
            Job(Pointer(to=counter).unsafe_origin_cast[MutUntrackedOrigin](), 0)
        )
    for i in range(8):
        assert_equal(
            external_call["pthread_create", Int32](
                Pointer(to=ids[i]),
                Optional[Raw](None),
                worker,
                Pointer(to=jobs[i]).unsafe_bitcast[UInt8](),
            ),
            0,
        )
    for id in ids:
        assert_equal(
            external_call["pthread_join", Int32](id, Optional[Raw](None)), 0
        )
    assert_equal(counter.load(), 800)
    for i in range(len(jobs)):
        assert_equal(jobs[i].done, 1)
    print(
        "native atomic, allocation, OpenSSL, and exception pthread smoke passed"
    )
