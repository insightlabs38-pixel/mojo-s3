"""Bounded test orchestration; each native process owns its S3 client/transport."""
import concurrent.futures
import subprocess
import sys
import time

executable = sys.argv[1]
start = time.monotonic()


def worker(_):
    return subprocess.run(
        [executable], check=True, capture_output=True, text=True, timeout=60
    )


with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    results = list(pool.map(worker, range(12)))
print(
    f'{len(results)} native contract runs passed with 4 concurrent processes in {time.monotonic()-start:.3f}s'
)
