#!/usr/bin/env python3
"""Print the authoritative file paths stored in an unencrypted Godot 4 PCK."""

from __future__ import annotations

import argparse
import struct
from pathlib import Path
from typing import BinaryIO


def read_exact(stream: BinaryIO, size: int) -> bytes:
    data = stream.read(size)
    if len(data) != size:
        raise ValueError("truncated PCK directory")
    return data


def read_u32(stream: BinaryIO) -> int:
    return struct.unpack("<I", read_exact(stream, 4))[0]


def list_paths(path: Path) -> list[str]:
    with path.open("rb") as stream:
        if read_exact(stream, 4) != b"GDPC":
            raise ValueError("not a Godot PCK")
        header = read_exact(stream, 36)
        pack_flags = struct.unpack_from("<I", header, 16)[0]
        directory_offset = struct.unpack_from("<Q", header, 28)[0]
        if pack_flags & 1:
            raise ValueError("encrypted PCK directories are not supported")
        stream.seek(directory_offset)
        file_count = read_u32(stream)
        paths: list[str] = []
        for _ in range(file_count):
            path_length = read_u32(stream)
            raw_path = read_exact(stream, path_length)
            paths.append(raw_path.rstrip(b"\0").decode("utf-8"))
            read_exact(stream, 8 + 8 + 16 + 4)
        return paths


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("pck", type=Path)
    args = parser.parse_args()
    for stored_path in list_paths(args.pck):
        print(stored_path)


if __name__ == "__main__":
    main()
