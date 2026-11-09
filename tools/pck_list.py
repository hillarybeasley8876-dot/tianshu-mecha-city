#!/usr/bin/env python3
"""Read-only: list the file table of a Godot 4 .pck (format v2/v3). Writes one path per line to stdout."""
import struct, sys
path = sys.argv[1]
with open(path, "rb") as f:
    head = f.read(4 + 4 * 5 + 8 + 8 + 64)
    if head[:4] != b"GDPC":
        sys.exit("not a GDPC pack")
    ver, maj, mnr, pat, flags = struct.unpack_from("<5I", head, 4)
    base = struct.unpack_from("<Q", head, 24)[0]
    if flags & 1:
        sys.exit("directory is encrypted")
    if ver >= 3:
        dir_off = struct.unpack_from("<Q", head, 32)[0]
        f.seek(dir_off)
    else:
        f.seek(4 + 4 * 5 + 8 + 64)
    count = struct.unpack("<I", f.read(4))[0]
    sys.stderr.write("PCK v%d engine %d.%d.%d flags=%d files=%d\n" % (ver, maj, mnr, pat, flags, count))
    for _ in range(count):
        n = struct.unpack("<I", f.read(4))[0]
        p = f.read(n).rstrip(b"\0").decode("utf-8", "replace")
        off, size = struct.unpack("<QQ", f.read(16))
        f.read(16)
        fl = struct.unpack("<I", f.read(4))[0] if ver >= 2 else 0
        print("%d\t%s" % (size, p))
