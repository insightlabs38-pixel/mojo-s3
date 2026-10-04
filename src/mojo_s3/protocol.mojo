"""S3 byte encoding, header normalization, and endpoint addressing."""
from std.collections import List


@fieldwise_init
struct Field(Copyable, Movable):
    var name: String
    var value: String


def uri_encode(value: String, preserve_slash: Bool = False) -> String:
    var result = String()
    var hex = "0123456789ABCDEF"
    for b in value.as_bytes():
        var n = Int(b)
        if (
            (n >= 65 and n <= 90)
            or (n >= 97 and n <= 122)
            or (n >= 48 and n <= 57)
            or n == 45
            or n == 46
            or n == 95
            or n == 126
            or (preserve_slash and n == 47)
        ):
            result += String(
                from_utf8_lossy=Span(unsafe_ptr=Pointer(to=b), length=1)
            )
        else:
            result += "%" + String(hex[byte=n >> 4]) + String(hex[byte=n & 15])
    return result


def sort_fields(mut fields: List[Field]):
    for i in range(1, len(fields)):
        var j = i
        while j > 0 and (
            fields[j].name < fields[j - 1].name
            or (
                fields[j].name == fields[j - 1].name
                and fields[j].value < fields[j - 1].value
            )
        ):
            var temp = fields[j].copy()
            fields[j] = fields[j - 1].copy()
            fields[j - 1] = temp^
            j -= 1


def canonical_query(fields: List[Field]) -> String:
    var encoded = List[Field]()
    for f in fields:
        encoded.append(Field(uri_encode(f.name), uri_encode(f.value)))
    sort_fields(encoded)
    var result = String()
    for i in range(len(encoded)):
        if i:
            result += "&"
        result += encoded[i].name + "=" + encoded[i].value
    return result


def normalize_space(value: String) raises -> String:
    var result = List[UInt8]()
    var space = False
    for b in value.as_bytes():
        if b < 32 and b != 9 or b == 127:
            raise Error("Invalid control character in HTTP header")
        if b == 32 or b == 9:
            space = len(result) > 0
        else:
            if space:
                result.append(32)
            result.append(b)
            space = False
    return String(
        from_utf8=Span(unsafe_ptr=result.unsafe_ptr(), length=len(result))
    )


def validate_header_name(name: String) raises:
    if not name:
        raise Error("Empty HTTP header name")
    for b in name.as_bytes():
        var n = Int(b)
        if not (
            (n >= 65 and n <= 90)
            or (n >= 97 and n <= 122)
            or (n >= 48 and n <= 57)
            or n == 45
            or String("!#$%&'*+.^_`|~").find(
                String(from_utf8_lossy=Span(unsafe_ptr=Pointer(to=b), length=1))
            )
            >= 0
        ):
            raise Error("Invalid HTTP header name")


def get_header(headers: List[Field], name: String) -> String:
    var result = String()
    for h in headers:
        if h.name.lower() == name.lower():
            if result:
                result += ","
            result += h.value
    return result


@fieldwise_init
struct Address(Copyable, Movable):
    var url: String
    var host: String
    var path: String


def address(
    endpoint: String, bucket: String, key: String, virtual_host: Bool = False
) raises -> Address:
    var split = endpoint.find("://")
    if split < 0:
        raise Error("Endpoint requires http:// or https://")
    var scheme = String(endpoint[byte=0:split])
    if scheme != "http" and scheme != "https":
        raise Error("Unsupported endpoint scheme")
    var rest = String(endpoint[byte = split + 3 :])
    if rest.find("?") >= 0 or rest.find("#") >= 0 or rest.find("@") >= 0:
        raise Error("Endpoint must not contain credentials, query, or fragment")
    var slash = rest.find("/")
    var host = rest
    var base = String()
    if slash >= 0:
        host = String(rest[byte=0:slash])
        base = String(rest[byte=slash:])
    while base.endswith("/"):
        var trimmed = String(base[byte = 0 : base.byte_length() - 1])
        base = trimmed
    if not host or not bucket or bucket.find("/") >= 0:
        raise Error("Endpoint host and bucket required")
    for b in host.as_bytes():
        if b <= 32 or b == 127:
            raise Error("Invalid endpoint authority")
    var path = uri_encode(base, True)
    if virtual_host:
        for b in bucket.as_bytes():
            if not (
                (b >= 97 and b <= 122)
                or (b >= 48 and b <= 57)
                or b == 45
                or b == 46
            ):
                raise Error("Virtual-host bucket must be DNS compatible")
        host = bucket + "." + host
    else:
        path += "/" + uri_encode(bucket)
    path += "/" + uri_encode(key, True)
    return Address(scheme + "://" + host + path, host, path)
