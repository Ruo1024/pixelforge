#!/usr/bin/env python3
"""Assemble and verify deterministic Beta 0.6 screenshot evidence."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from collections import Counter
from pathlib import Path
import struct
import time
import zlib


EXPECTED = {
    "1080x560-en-100-closed.png": "closed",
    "1080x560-zh-50-overlay.png": "overlay",
    "1280x720-en-50-batch-12-13.png": "batch_12_13",
    "1280x720-zh-100-inspector.png": "inspector",
    "1440x900-en-50-batch-50-all.png": "batch_50",
    "1440x900-zh-100-card-families.png": "card_families",
    "1440x900-en-400-inspect.png": "inspect",
}
REQUIRED_ENTRY_KEYS = {
    "scenario",
    "requested_locale",
    "actual_locale",
    "png_size",
    "ui_scale",
    "camera_zoom",
    "zoom_index",
    "zoom_label",
    "drawer_rect",
    "drawer_mode",
    "toolbar_mode",
    "batch_counts",
    "card_bounds",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def assemble(args: argparse.Namespace) -> None:
    output = Path(args.output)
    metadata_root = Path(args.metadata)
    status = Path(args.git_status_file).read_text(encoding="utf-8")
    entries = []
    for filename, scenario in EXPECTED.items():
        path = output / filename
        metadata_path = metadata_root / f"{scenario}.json"
        entry = json.loads(metadata_path.read_text(encoding="utf-8"))
        entry.update(
            {
                "filename": filename,
                "png_sha256": sha256(path),
                "git_head": args.git_head,
                "git_dirty": bool(status.strip()),
            }
        )
        entries.append(entry)
    manifest = {
        "schema_version": 1,
        "generated_unix": int(time.time()),
        "git_head": args.git_head,
        "git_dirty": bool(status.strip()),
        "entries": entries,
    }
    (output / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


def _paeth(left: int, above: int, upper_left: int) -> int:
    estimate = left + above - upper_left
    left_distance = abs(estimate - left)
    above_distance = abs(estimate - above)
    upper_left_distance = abs(estimate - upper_left)
    if left_distance <= above_distance and left_distance <= upper_left_distance:
        return left
    if above_distance <= upper_left_distance:
        return above
    return upper_left


def png_rgb_counts(path: Path) -> tuple[int, int, Counter[tuple[int, int, int]]]:
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"not a PNG: {path}")
    offset = 8
    width = height = bit_depth = color_type = interlace = 0
    compressed = bytearray()
    while offset < len(data):
        length = struct.unpack(">I", data[offset : offset + 4])[0]
        kind = data[offset + 4 : offset + 8]
        payload = data[offset + 8 : offset + 8 + length]
        offset += length + 12
        if kind == b"IHDR":
            width, height, bit_depth, color_type, _, _, interlace = struct.unpack(
                ">IIBBBBB", payload
            )
        elif kind == b"IDAT":
            compressed.extend(payload)
        elif kind == b"IEND":
            break
    if bit_depth != 8 or color_type not in (2, 6) or interlace != 0:
        raise ValueError(
            f"unsupported PNG encoding in {path}: depth={bit_depth}, "
            f"color={color_type}, interlace={interlace}"
        )
    channels = 3 if color_type == 2 else 4
    row_bytes = width * channels
    raw = zlib.decompress(bytes(compressed))
    expected_bytes = height * (row_bytes + 1)
    if len(raw) != expected_bytes:
        raise ValueError(f"unexpected decoded PNG size in {path}")
    previous = bytearray(row_bytes)
    cursor = 0
    counts: Counter[tuple[int, int, int]] = Counter()
    for _ in range(height):
        filter_type = raw[cursor]
        cursor += 1
        encoded = raw[cursor : cursor + row_bytes]
        cursor += row_bytes
        row = bytearray(row_bytes)
        for index, value in enumerate(encoded):
            left = row[index - channels] if index >= channels else 0
            above = previous[index]
            upper_left = previous[index - channels] if index >= channels else 0
            if filter_type == 0:
                decoded = value
            elif filter_type == 1:
                decoded = value + left
            elif filter_type == 2:
                decoded = value + above
            elif filter_type == 3:
                decoded = value + ((left + above) // 2)
            elif filter_type == 4:
                decoded = value + _paeth(left, above, upper_left)
            else:
                raise ValueError(f"unknown PNG filter {filter_type} in {path}")
            row[index] = decoded & 0xFF
        for index in range(0, row_bytes, channels):
            counts[(row[index], row[index + 1], row[index + 2])] += 1
        previous = row
    return width, height, counts


def verify(args: argparse.Namespace) -> None:
    output = Path(args.output)
    expected_files = set(EXPECTED) | {"manifest.json"}
    actual_files = {path.name for path in output.iterdir() if path.is_file()}
    if actual_files != expected_files:
        raise SystemExit(
            f"evidence file set mismatch: expected={sorted(expected_files)}, "
            f"actual={sorted(actual_files)}"
        )
    manifest = json.loads((output / "manifest.json").read_text(encoding="utf-8"))
    entries = {entry["filename"]: entry for entry in manifest.get("entries", [])}
    if set(entries) != set(EXPECTED):
        raise SystemExit("manifest entries do not match the seven fixed screenshots")
    hashes = set()
    for filename, scenario in EXPECTED.items():
        path = output / filename
        if path.stat().st_mtime + 0.001 < args.started_unix:
            raise SystemExit(f"stale screenshot mtime: {filename}")
        width, height, counts = png_rgb_counts(path)
        dimensions = filename.split("-", 1)[0]
        expected_width, expected_height = map(int, dimensions.split("x"))
        if (width, height) != (expected_width, expected_height):
            raise SystemExit(
                f"PNG dimensions mismatch for {filename}: {(width, height)}"
            )
        if len(counts) < 32:
            raise SystemExit(f"fewer than 32 RGB colors in {filename}")
        total = width * height
        majority = counts.most_common(1)[0][1]
        if (total - majority) / total < 0.01:
            raise SystemExit(f"fewer than 1% pixels differ from background in {filename}")
        digest = sha256(path)
        if digest in hashes:
            raise SystemExit(f"duplicate screenshot SHA-256: {filename}")
        hashes.add(digest)
        entry = entries[filename]
        missing = REQUIRED_ENTRY_KEYS - set(entry)
        if missing:
            raise SystemExit(f"manifest keys missing for {filename}: {sorted(missing)}")
        if entry["scenario"] != scenario:
            raise SystemExit(f"scenario mismatch for {filename}")
        if entry["actual_locale"] != entry["requested_locale"]:
            raise SystemExit(f"locale mismatch for {filename}")
        if entry["png_size"] != [width, height]:
            raise SystemExit(f"manifest dimensions mismatch for {filename}")
        if entry["png_sha256"] != digest:
            raise SystemExit(f"manifest SHA-256 mismatch for {filename}")


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser()
    commands = root.add_subparsers(dest="command", required=True)
    assemble_parser = commands.add_parser("assemble")
    assemble_parser.add_argument("--output", required=True)
    assemble_parser.add_argument("--metadata", required=True)
    assemble_parser.add_argument("--git-head", required=True)
    assemble_parser.add_argument("--git-status-file", required=True)
    assemble_parser.set_defaults(func=assemble)
    verify_parser = commands.add_parser("verify")
    verify_parser.add_argument("--output", required=True)
    verify_parser.add_argument("--started-unix", required=True, type=float)
    verify_parser.set_defaults(func=verify)
    return root


def main() -> None:
    args = parser().parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
