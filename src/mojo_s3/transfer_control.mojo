"""Owned transfer counters/cancellation; observers execute on the coordinator."""
from std.atomic import Atomic
from std.collections import List
from std.ffi import external_call
from std.os import abort as process_abort
from std.time import sleep


@fieldwise_init
struct TransferProgress(Copyable, Movable):
    var completed_bytes: Int
    var total_bytes: Int
    var completed_parts: Int
    var cancelled: Bool


trait ProgressObserver(Movable):
    def on_progress(mut self, progress: TransferProgress) raises:
        ...


struct NoProgress(ProgressObserver):
    def __init__(out self):
        pass

    def on_progress(mut self, progress: TransferProgress):
        pass


struct TransferState(Movable):
    var cancelled: Atomic[Int32]
    var completed_bytes: Atomic[Int64]
    var completed_parts: Atomic[Int64]
    var total_bytes: Atomic[Int64]
    var observer_failed: Atomic[Int32]

    def __init__(out self):
        self.cancelled = Atomic[Int32](0)
        self.completed_bytes = Atomic[Int64](0)
        self.completed_parts = Atomic[Int64](0)
        self.total_bytes = Atomic[Int64](0)
        self.observer_failed = Atomic[Int32](0)


struct TransferControl(Movable):
    var state: List[TransferState]

    def __init__(out self):
        self.state = List[TransferState]()
        self.state.append(TransferState())

    def cancel(mut self):
        self.state[0].cancelled.store(1)

    def is_cancelled(self) -> Bool:
        return self.state[0].cancelled.load() != 0

    def progress(self) -> TransferProgress:
        return TransferProgress(
            Int(self.state[0].completed_bytes.load()),
            Int(self.state[0].total_bytes.load()),
            Int(self.state[0].completed_parts.load()),
            self.is_cancelled(),
        )

    def record_progress(mut self, bytes: Int):
        _ = self.state[0].completed_bytes.fetch_add(Int64(bytes))
        _ = self.state[0].completed_parts.fetch_add(1)

    def mark_observer_failed(mut self):
        self.state[0].observer_failed.store(1)
        self.cancel()

    def observer_failed(self) -> Bool:
        return self.state[0].observer_failed.load() != 0

    def start(mut self, total: Int) raises:
        if total < 0:
            raise Error("Invalid transfer total")
        self.state[0].completed_bytes.store(0)
        self.state[0].completed_parts.store(0)
        self.state[0].total_bytes.store(Int64(total))
        self.state[0].observer_failed.store(0)


def join_observed[
    Observer: ProgressObserver
](
    threads: List[UInt],
    launched: Int,
    mut control: TransferControl,
    mut observer: Observer,
) raises:
    var joined = List[Bool](length=launched, fill=False)
    var remaining = launched
    while remaining:
        for i in range(launched):
            if joined[i]:
                continue
            var code = external_call["pthread_tryjoin_np", Int32](
                threads[i], Int(0)
            )
            if code == 0:
                joined[i] = True
                remaining -= 1
            elif code != 16:  # Linux EBUSY
                process_abort()  # Never free contexts whose threads may be live.
        if not control.observer_failed():
            try:
                observer.on_progress(control.progress())
            except:
                control.mark_observer_failed()
        if remaining:
            sleep(0.01)
    if control.observer_failed():
        raise Error("Transfer progress observer failed; all workers joined")
