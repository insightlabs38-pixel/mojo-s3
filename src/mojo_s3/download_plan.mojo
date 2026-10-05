"""Bounded download scheduling independent of payload and outcome allocation."""
from mojo_s3.multipart_plan import MAX_MULTIPART_BYTES


@fieldwise_init
struct DownloadPlan(Copyable, Movable):
    var range_size_bytes: Int64
    var range_count: Int
    var workers: Int


def plan_download(
    size_bytes: Int64,
    target_range_bytes: Int64,
    workers: Int,
    buffer_budget_bytes: Int64,
) raises -> DownloadPlan:
    if (
        size_bytes < 0
        or size_bytes > MAX_MULTIPART_BYTES
        or target_range_bytes < 1
        or workers < 1
        or workers > 16
        or buffer_budget_bytes < 1
    ):
        raise Error("Invalid download plan")
    var minimum_range = (
        size_bytes - 1
    ) // 1000000 + 1 if size_bytes else Int64(1)
    var range_bytes = max(
        min(min(target_range_bytes, 64 * 1024 * 1024), buffer_budget_bytes),
        minimum_range,
    )
    if range_bytes > 64 * 1024 * 1024 or range_bytes > buffer_budget_bytes:
        raise Error(
            "Download buffer budget cannot fit a bounded plan; use streamed download or increase the budget"
        )
    var selected_workers = min(workers, Int(buffer_budget_bytes // range_bytes))
    var count = Int((size_bytes - 1) // range_bytes + 1) if size_bytes else 0
    return DownloadPlan(range_bytes, count, min(selected_workers, count))
