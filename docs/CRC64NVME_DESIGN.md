# CRC64NVME evaluation — deferred

No CRC64NVME implementation is added in this pass. Its algorithm is small, but
correct end-to-end support requires a checksum-state/wire lifecycle change beyond
this API freeze. Live AWS negotiation remains unqualified. The current SDK retains
returned CRC64NVME metadata as **unverified**, not silently verified or discarded.

Independent catalogue parameters for CRC-64/NVME are width 64, polynomial
`0xad93d23594c93659`, initial/final XOR `0xffffffffffffffff`, input/output reflected,
and check value `0xae8b14860a799888` for ASCII `123456789`. These are specified
parameters, not trial-and-error deductions. A future implementation must compare
incremental/split/empty/binary vectors with an independent implementation such as
AWS CRT and serialize the finalized 8-byte digest in big-endian Base64 wire form.
No independent implementation execution is claimed by this design-only pass.

| Path | Required change and oracle |
|---|---|
| Buffered PutObject | UInt64 digest, explicit algorithm validation, x-amz-checksum-crc64nvme/Base64 header and returned checksum comparison; independent body/header oracle. |
| Streamed file PutObject | Incremental UInt64 state in bounded existing reads; empty/tail/split/offset vectors, source immutability, no whole-file allocation. Touching this path requires repeating the 5 GiB wire control. |
| GET/file download | Only compare supported, declared full-object digests against all object bytes before committing the file. Ranged responses cannot establish the entire object's checksum. |
| Multipart initiation | Explicit CRC64NVME algorithm and FULL_OBJECT type; preserve negotiated state across operations rather than infer it from one response header. |
| UploadPart | Optional part checksum fields and validation as allowed by the API; these do not turn a part checksum into a full-object checksum. |
| Completion | Explicit full-object checksum/type (and required object size), negotiated manifest semantics, service rejection/ambiguous completion/corruption oracles. A streamed whole-file digest may avoid CRC composition but adds an extra full-source pass. |
| Multipart copy | Payload-free client cannot independently hash copied source bytes. A returned full-object checksum is metadata until independently verified; do not claim verification from ETag, source HEAD or part hashes. |
| Metadata/state | Represent algorithm, full-object/composite kind, returned value and actual verification separately, including conflicts and unsupported algorithms. |

AWS currently permits CRC64NVME multipart **full-object only**; CRC32/CRC32C can
be full-object or composite, while SHA1/SHA256 multipart are composite. Therefore
CRC64NVME is not added by reusing the existing composite parser or concatenating
part digests. Multipart composition/negotiation remains deferred. No new XXHash,
SHA512 or MD5 algorithm surface is introduced.

References (retrieved October 5, 2026):

- [CRC catalogue](https://reveng.sourceforge.io/crc-catalogue/17plus.htm#crc.cat.crc-64-nvme)
- [AWS integrity and checksum types](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity-upload.html)
- [PutObject](https://docs.aws.amazon.com/AmazonS3/latest/API/API_PutObject.html)
- [CompleteMultipartUpload](https://docs.aws.amazon.com/AmazonS3/latest/API/API_CompleteMultipartUpload.html)
