"""Bounded libxml2 pull-reader for S3 response documents.

DTD/entity-reference nodes are rejected, network loading is disabled, and no
entity expansion flags are enabled. Namespace prefixes are intentionally ignored.
"""
from std.collections import List
from std.ffi import external_call
from std.memory import Pointer

comptime Raw = Pointer[UInt8, MutUntrackedOrigin]


@fieldwise_init
struct XmlNode(Copyable, Movable):
    var name: String
    var text: String
    var parent: Int


struct Reader(Movable):
    var ptr: Raw

    def __init__(out self, text: String) raises:
        if text.byte_length() > 8 * 1024 * 1024:
            raise Error("XML exceeds 8 MiB limit")
        var p = external_call["xmlReaderForMemory", Optional[Raw]](
            text.unsafe_ptr(),
            Int32(text.byte_length()),
            Optional[Raw](None),
            Optional[Raw](None),
            Int32(2048 | 32 | 64),
        )
        if not p:
            raise Error("Cannot initialize XML reader")
        self.ptr = p.value()

    def __deinit__(deinit self):
        external_call["xmlFreeTextReader", NoneType](self.ptr)


def c_text(ptr: Optional[Raw]) raises -> String:
    if not ptr:
        return ""
    var p = ptr.value()
    var n = external_call["strlen", Int](p)
    return String(from_utf8=Span(unsafe_ptr=p, length=n))


def parse_xml(text: String) raises -> List[XmlNode]:
    var reader = Reader(text)
    var nodes = List[XmlNode]()
    var parents = List[Int]()
    while True:
        var read = external_call["xmlTextReaderRead", Int32](reader.ptr)
        if read == 0:
            break
        if read < 0:
            raise Error("Malformed S3 XML")
        var kind = external_call["xmlTextReaderNodeType", Int32](reader.ptr)
        var depth = Int(external_call["xmlTextReaderDepth", Int32](reader.ptr))
        if depth > 64 or len(nodes) > 100000:
            raise Error("XML structure exceeds limits")
        if kind == 10 or kind == 5:
            raise Error("DTD and entity references are forbidden in S3 XML")
        if kind == 1:
            while len(parents) > depth:
                _ = parents.pop()
            var parent = -1
            if depth:
                if len(parents) != depth:
                    raise Error("Invalid XML nesting")
                parent = parents[depth - 1]
            var name = c_text(
                external_call["xmlTextReaderConstLocalName", Optional[Raw]](
                    reader.ptr
                )
            )
            nodes.append(XmlNode(name, "", parent))
            parents.append(len(nodes) - 1)
        elif kind == 3 or kind == 4 or kind == 13 or kind == 14:
            if depth and len(parents) >= depth:
                var value = c_text(
                    external_call["xmlTextReaderConstValue", Optional[Raw]](
                        reader.ptr
                    )
                )
                nodes[parents[depth - 1]].text += value
    if not len(nodes):
        raise Error("Empty S3 XML")
    return nodes^


def child_text(
    nodes: List[XmlNode], parent: Int, name: String
) raises -> String:
    var value = String()
    var found = False
    for n in nodes:
        if n.parent == parent and n.name == name:
            if found:
                raise Error("Duplicate S3 XML element: " + name)
            found = True
            value = n.text
    return value
