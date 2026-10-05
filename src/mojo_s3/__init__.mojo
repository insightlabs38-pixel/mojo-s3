"""Native S3 SDK public facade; see docs/API.md for stability and ownership."""
from mojo_s3.client import S3Store
from mojo_s3.config import S3Config
from mojo_s3.signing import Credentials
from mojo_s3.errors import S3Error
from mojo_s3.protocol import Field
from mojo_s3.transfers import TransferManager, TransferOptions
from mojo_s3.multipart_plan import MultipartPlan, plan_multipart
from mojo_s3.multipart_inspection import (
    UploadedPart,
    PartsPage,
    MultipartUpload,
    MultipartUploadsPage,
    PartsPaginator,
    MultipartUploadsPaginator,
    list_parts,
    list_multipart_uploads,
)
from mojo_s3.multipart_copy import upload_part_copy, multipart_copy_object
from mojo_s3.tagging import (
    get_object_tagging,
    put_object_tagging,
    delete_object_tagging,
)
from mojo_s3.objects import (
    ObjectStore,
    ObjectMetadata,
    ObjectInfo,
    GetResult,
    PutResult,
    ListResult,
    PutOptions,
    ListOptions,
    ListPaginator,
    ObjectRange,
    Conditions,
    ReadOptions,
    CopyOptions,
    CopyResult,
    ObjectIdentifier,
    BatchDeleteResult,
    DeleteFailure,
)

from mojo_s3.identity import (
    CredentialSnapshot,
    CredentialSource,
    CredentialCache,
    workload_source_from_env,
)

from mojo_s3.transfer_control import (
    TransferControl,
    TransferProgress,
    ProgressObserver,
)
