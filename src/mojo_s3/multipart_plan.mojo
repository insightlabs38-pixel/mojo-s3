"""Allocation-free 64-bit multipart planning from published S3 part limits."""

comptime MIN_PART_BYTES: Int64 = 5 * 1024 * 1024
comptime MAX_PART_BYTES: Int64 = 5 * 1024 * 1024 * 1024
comptime MAX_PARTS: Int = 10000
comptime MAX_MULTIPART_BYTES: Int64 = MAX_PART_BYTES * Int64(MAX_PARTS)
comptime FILE_BUFFER_BYTES: Int = 65536


@fieldwise_init
struct MultipartPlan(Copyable, Movable):
    var size_bytes: Int64
    var part_size_bytes: Int64
    var part_count: Int

    def offset(self, number: Int) raises -> Int64:
        if number < 1 or number > self.part_count:
            raise Error("Part number outside multipart plan")
        return Int64(number - 1) * self.part_size_bytes

    def length(self, number: Int) raises -> Int64:
        return min(self.part_size_bytes, self.size_bytes - self.offset(number))


def plan_multipart(
    size_bytes: Int64, target_part_bytes: Int64 = 8 * 1024 * 1024
) raises -> MultipartPlan:
    if size_bytes < 0 or size_bytes > MAX_MULTIPART_BYTES:
        raise Error("Object size exceeds the supported S3 multipart capacity")
    if target_part_bytes < MIN_PART_BYTES or target_part_bytes > MAX_PART_BYTES:
        raise Error("Multipart target part size must be 5 MiB..5 GiB")
    if size_bytes == 0:
        return MultipartPlan(0, target_part_bytes, 0)
    # Subtract before dividing: no size+divisor overflow even at Int64 boundaries.
    var required = (size_bytes - 1) // Int64(MAX_PARTS) + 1
    var selected = max(target_part_bytes, required)
    var count = (size_bytes - 1) // selected + 1
    if selected > MAX_PART_BYTES or count > Int64(MAX_PARTS):
        raise Error("Object cannot fit within S3 multipart bounds")
    return MultipartPlan(size_bytes, selected, Int(count))
