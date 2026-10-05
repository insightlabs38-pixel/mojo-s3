"""Read listings page by page, preserving common prefixes and continuation state."""
from std.os import getenv
from mojo_s3.client import S3Store
from mojo_s3.config import S3Config
from mojo_s3.objects import ListOptions, ListPaginator


def main() raises:
    var store = S3Store(S3Config.from_env())
    var paginator = ListPaginator(
        getenv("S3_TEST_BUCKET", "mojo-test"),
        ListOptions(
            prefix=getenv("S3_LIST_PREFIX", ""), delimiter="/", max_keys=100
        ),
    )
    while not paginator.done:
        var page = paginator.next_page(store)
        for object in page.objects:
            print(object.key, object.size)
        for prefix in page.prefixes:
            print("Prefix:", prefix)
        print("Page:", paginator.pages_loaded, "Truncated:", page.truncated)
