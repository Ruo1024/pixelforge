#!/usr/bin/env python3
"""Assemble and verify deterministic Beta 0.7 screenshot evidence."""

from __future__ import annotations

import argparse
import hashlib
import json
import struct
import time
import zlib
from pathlib import Path


SENTINEL = b"PF_B7_CREDENTIAL_SENTINEL_7B1E9C42"
EXPECTED = {
    "1280x720-en-100-example-reflow.png": "example_reflow",
    "1440x900-zh-100-generation-ready.png": "generation_ready",
    "1440x900-en-100-running-output-edge.png": "running_output_edge",
    "1440x900-zh-100-output-12.png": "output_12",
    "1440x900-en-100-output-13-50-scroll.png": "output_13_50_scroll",
    "2560x1440-en-100-reference-12.png": "reference_12",
    "1440x900-zh-100-detached-sprite.png": "detached_sprite",
    "1440x900-en-100-cleanup-running.png": "cleanup_running",
    "1080x560-zh-150-partial-dialog.png": "partial_dialog",
}
REQUIRED_KEYS = {
    "scenario", "requested_locale", "actual_locale", "png_size", "ui_scale",
    "components", "slot_count", "internal_scroll", "safe_fixture_origin",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def png_info(path: Path) -> tuple[int, int, int, float]:
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"not PNG: {path.name}")
    offset = 8
    width = height = color_type = bit_depth = interlace = 0
    compressed = bytearray()
    while offset < len(data):
        length = struct.unpack(">I", data[offset:offset + 4])[0]
        kind = data[offset + 4:offset + 8]
        payload = data[offset + 8:offset + 8 + length]
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
        raise SystemExit(f"unsupported PNG encoding: {path.name}")
    channels = 3 if color_type == 2 else 4
    row_bytes = width * channels
    raw = zlib.decompress(bytes(compressed))
    previous = bytearray(row_bytes)
    cursor = 0
    colors: set[bytes] = set()
    changed = 0
    background = None
    for _ in range(height):
        filter_type = raw[cursor]
        cursor += 1
        encoded = raw[cursor:cursor + row_bytes]
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
                estimate = left + above - upper_left
                distances = (abs(estimate - left), abs(estimate - above), abs(estimate - upper_left))
                decoded = value + (left, above, upper_left)[distances.index(min(distances))]
            else:
                raise SystemExit(f"unknown PNG filter: {path.name}")
            row[index] = decoded & 0xFF
        for index in range(0, row_bytes, channels):
            rgb = bytes(row[index:index + 3])
            colors.add(rgb)
            if background is None:
                background = rgb
            if rgb != background:
                changed += 1
        previous = row
    return width, height, len(colors), changed / max(1, width * height)


def assemble(args: argparse.Namespace) -> None:
    output = Path(args.output)
    metadata = Path(args.metadata)
    entries = []
    for filename, scenario in EXPECTED.items():
        entry = json.loads((metadata / f"{scenario}.json").read_text(encoding="utf-8"))
        entry.update({"filename": filename, "png_sha256": sha256(output / filename)})
        entries.append(entry)
    manifest = {
        "schema_version": 1,
        "generated_unix": int(time.time()),
        "git_head": args.git_head,
        "credential_sentinel_scan": {
            "sentinel_sha256": hashlib.sha256(SENTINEL).hexdigest(),
            "files_scanned": len(entries) * 2 + 1,
            "found": False,
        },
        "entries": entries,
    }
    manifest_path = output / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    for path in list(output.iterdir()) + list(metadata.iterdir()):
        if path.is_file() and SENTINEL in path.read_bytes():
            raise SystemExit(f"credential sentinel leaked into evidence: {path.name}")


def verify(args: argparse.Namespace) -> None:
    output = Path(args.output)
    expected_files = set(EXPECTED) | {"manifest.json"}
    actual_files = {path.name for path in output.iterdir() if path.is_file()}
    if actual_files != expected_files:
        raise SystemExit("evidence file set mismatch")
    manifest_path = output / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if SENTINEL in manifest_path.read_bytes() or manifest["credential_sentinel_scan"]["found"]:
        raise SystemExit("credential sentinel manifest guard failed")
    entries = {entry["filename"]: entry for entry in manifest.get("entries", [])}
    if set(entries) != set(EXPECTED):
        raise SystemExit("manifest does not contain the exact screenshot set")
    digests = set()
    for filename, scenario in EXPECTED.items():
        path = output / filename
        if path.stat().st_mtime + 0.001 < args.started_unix:
            raise SystemExit(f"stale screenshot: {filename}")
        width, height, color_count, changed_ratio = png_info(path)
        expected_size = tuple(map(int, filename.split("-", 1)[0].split("x")))
        if (width, height) != expected_size or color_count < 24 or changed_ratio < 0.01:
            raise SystemExit(f"invalid screenshot structure: {filename}")
        digest = sha256(path)
        if digest in digests:
            raise SystemExit(f"duplicate screenshot: {filename}")
        digests.add(digest)
        entry = entries[filename]
        if REQUIRED_KEYS - set(entry):
            raise SystemExit(f"manifest keys missing: {filename}")
        if entry["scenario"] != scenario or entry["actual_locale"] != entry["requested_locale"]:
            raise SystemExit(f"scenario or locale mismatch: {filename}")
        if entry["png_size"] != [width, height] or entry["png_sha256"] != digest:
            raise SystemExit(f"size or hash mismatch: {filename}")


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser()
    commands = root.add_subparsers(dest="command", required=True)
    assemble_parser = commands.add_parser("assemble")
    assemble_parser.add_argument("--output", required=True)
    assemble_parser.add_argument("--metadata", required=True)
    assemble_parser.add_argument("--git-head", required=True)
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
