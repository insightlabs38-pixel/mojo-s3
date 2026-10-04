"""Deterministic AWS Signature Version 4; timestamps are explicit inputs."""
from std.collections import List
from mojo_s3.crypto import bytes_of, hmac_sha256, hex_encode, hash_text
from mojo_s3.protocol import (
    Field,
    canonical_query,
    sort_fields,
    normalize_space,
    validate_header_name,
)


@fieldwise_init
struct Credentials(Copyable, Movable):
    var access_key: String
    var secret_key: String
    var session_token: String


@fieldwise_init
struct Signature(Copyable, Movable):
    var authorization: String
    var canonical_request: String
    var string_to_sign: String
    var signature: String
    var signed_headers: String


def validate_timestamp(timestamp: String) raises:
    if (
        timestamp.byte_length() != 16
        or timestamp.as_bytes()[8] != 84
        or timestamp.as_bytes()[15] != 90
    ):
        raise Error("Timestamp must be YYYYMMDDTHHMMSSZ")
    for i in range(16):
        if i != 8 and i != 15:
            var b = timestamp.as_bytes()[i]
            if b < 48 or b > 57:
                raise Error("Invalid timestamp")


def signature_for(
    credentials: Credentials,
    region: String,
    service: String,
    timestamp: String,
    canonical: String,
) raises -> Signature:
    validate_timestamp(timestamp)
    if (
        not credentials.access_key
        or not credentials.secret_key
        or not region
        or not service
    ):
        raise Error("Credentials, region, and service required")
    var date = String(timestamp[byte=0:8])
    var scope = date + "/" + region + "/" + service + "/aws4_request"
    var to_sign = (
        "AWS4-HMAC-SHA256\n"
        + timestamp
        + "\n"
        + scope
        + "\n"
        + hash_text(canonical)
    )
    var date_key = hmac_sha256(
        bytes_of("AWS4" + credentials.secret_key), bytes_of(date)
    )
    var region_key = hmac_sha256(date_key, bytes_of(region))
    var service_key = hmac_sha256(region_key, bytes_of(service))
    var signing_key = hmac_sha256(service_key, bytes_of("aws4_request"))
    var sig = hex_encode(hmac_sha256(signing_key, bytes_of(to_sign)))
    return Signature("", canonical, to_sign, sig, "")


def sign(
    credentials: Credentials,
    region: String,
    service: String,
    method: String,
    path: String,
    query: List[Field],
    headers: List[Field],
    payload_hash: String,
    timestamp: String,
) raises -> Signature:
    var sorted = List[Field]()
    for h in headers:
        validate_header_name(h.name)
        if h.name.lower() == "authorization":
            raise Error("Authorization cannot be included in signed headers")
        # Combine duplicate headers in original wire order, then sort names.
        var name = h.name.lower()
        var value = normalize_space(h.value)
        var found = False
        for i in range(len(sorted)):
            if sorted[i].name == name:
                sorted[i].value += "," + value
                found = True
                break
        if not found:
            sorted.append(Field(name, value))
    sort_fields(sorted)
    var canonical_headers = String()
    var names = String()
    for h in sorted:
        canonical_headers += h.name + ":" + h.value + "\n"
        if names:
            names += ";"
        names += h.name
    var canonical = (
        method
        + "\n"
        + path
        + "\n"
        + canonical_query(query)
        + "\n"
        + canonical_headers
        + "\n"
        + names
        + "\n"
        + payload_hash
    )
    var result = signature_for(
        credentials, region, service, timestamp, canonical
    )
    var scope = (
        String(timestamp[byte=0:8])
        + "/"
        + region
        + "/"
        + service
        + "/aws4_request"
    )
    result.signed_headers = names
    result.authorization = (
        "AWS4-HMAC-SHA256 Credential="
        + credentials.access_key
        + "/"
        + scope
        + ", SignedHeaders="
        + names
        + ", Signature="
        + result.signature
    )
    return result^
