"""Bounded flat string JSON reader for AWS credential endpoint responses."""
from std.collections import List
from mojo_s3.protocol import Field


struct CredentialJson(Movable):
    var text: String
    var pos: Int

    def __init__(out self, text: String) raises:
        if text.byte_length() > 65536:
            raise Error("Credential response exceeds limit")
        self.text = text
        self.pos = 0

    def space(mut self):
        while self.pos < self.text.byte_length() and Int(
            self.text.as_bytes()[self.pos]
        ) in [9, 10, 13, 32]:
            self.pos += 1

    def expect(mut self, b: UInt8) raises:
        self.space()
        if (
            self.pos >= self.text.byte_length()
            or self.text.as_bytes()[self.pos] != b
        ):
            raise Error("Malformed credential JSON")
        self.pos += 1

    def hex4(mut self) raises -> Int:
        var value = 0
        for _ in range(4):
            if self.pos >= self.text.byte_length():
                raise Error("Truncated JSON escape")
            var b = Int(self.text.as_bytes()[self.pos])
            self.pos += 1
            var digit = (
                b - 48 if 48
                <= b
                <= 57 else b - 87 if 97
                <= b
                <= 102 else b - 55 if 65
                <= b
                <= 70 else -1
            )
            if digit < 0:
                raise Error("Invalid JSON escape")
            value = value * 16 + digit
        return value

    def string(mut self) raises -> String:
        self.expect(34)
        var bytes = List[UInt8]()
        while self.pos < self.text.byte_length():
            var b = self.text.as_bytes()[self.pos]
            self.pos += 1
            if b == 34:
                return String(
                    from_utf8=Span(
                        unsafe_ptr=bytes.unsafe_ptr(), length=len(bytes)
                    )
                )
            if b < 32:
                raise Error("Control byte in credential JSON")
            if b != 92:
                bytes.append(b)
                continue
            if self.pos >= self.text.byte_length():
                raise Error("Truncated JSON escape")
            b = self.text.as_bytes()[self.pos]
            self.pos += 1
            if Int(b) in [34, 47, 92]:
                bytes.append(b)
            elif Int(b) in [98, 102, 110, 114, 116]:
                bytes.append(
                    UInt8(
                        8 if b
                        == 98 else 12 if b
                        == 102 else 10 if b
                        == 110 else 13 if b
                        == 114 else 9
                    )
                )
            elif b == 117:
                var cp = self.hex4()
                if 0xD800 <= cp <= 0xDBFF:
                    if (
                        self.pos + 2 > self.text.byte_length()
                        or self.text.as_bytes()[self.pos] != 92
                        or self.text.as_bytes()[self.pos + 1] != 117
                    ):
                        raise Error("Missing JSON low surrogate")
                    self.pos += 2
                    var low = self.hex4()
                    if low < 0xDC00 or low > 0xDFFF:
                        raise Error("Invalid JSON surrogate")
                    cp = 0x10000 + (cp - 0xD800) * 1024 + low - 0xDC00
                elif 0xDC00 <= cp <= 0xDFFF:
                    raise Error("Invalid JSON surrogate")
                if cp < 128:
                    bytes.append(UInt8(cp))
                elif cp < 2048:
                    bytes.append(UInt8(192 | (cp >> 6)))
                    bytes.append(UInt8(128 | (cp & 63)))
                elif cp < 65536:
                    bytes.append(UInt8(224 | (cp >> 12)))
                    bytes.append(UInt8(128 | ((cp >> 6) & 63)))
                    bytes.append(UInt8(128 | (cp & 63)))
                else:
                    bytes.append(UInt8(240 | (cp >> 18)))
                    bytes.append(UInt8(128 | ((cp >> 12) & 63)))
                    bytes.append(UInt8(128 | ((cp >> 6) & 63)))
                    bytes.append(UInt8(128 | (cp & 63)))
            else:
                raise Error("Invalid JSON escape")
        raise Error("Unterminated credential JSON string")

    def fields(mut self) raises -> List[Field]:
        self.expect(123)
        var fields = List[Field]()
        self.space()
        if (
            self.pos < self.text.byte_length()
            and self.text.as_bytes()[self.pos] == 125
        ):
            self.pos += 1
        else:
            while True:
                var name = self.string()
                for field in fields:
                    if field.name == name:
                        raise Error("Duplicate credential JSON field")
                self.expect(58)
                var value = self.string()
                fields.append(Field(name, value))
                if len(fields) > 32:
                    raise Error("Too many credential JSON fields")
                self.space()
                if (
                    self.pos < self.text.byte_length()
                    and self.text.as_bytes()[self.pos] == 125
                ):
                    self.pos += 1
                    break
                self.expect(44)
        self.space()
        if self.pos != self.text.byte_length():
            raise Error("Trailing credential JSON data")
        return fields^
