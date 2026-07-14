#!/usr/bin/env python3
"""Fail if a candidate contains protected paths, user material, or live secret values."""

from __future__ import annotations

import argparse
import os
import re
from pathlib import Path


FORBIDDEN_PATH = re.compile(
    r"(^|/)(test picture|tests/fixtures/real|scratch|垃圾桶|godot-interactive-guide)(/|$)",
    re.IGNORECASE,
)
USER_MATERIAL = re.compile(
    r"(^|/)(credentials\.cfg|\.env(?:\..*)?|[^/]+\.(?:pxproj|log))$", re.IGNORECASE
)
SECRET_NAME = re.compile(r"(key|token|secret|password|credential|auth)", re.IGNORECASE)
KNOWN_SENTINELS = [b"PF_B7_CREDENTIAL_SENTINEL_7B1E9C42", b"PF_SECRET_SENTINEL_DO_NOT_LEAK"]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--pck-paths", required=True, type=Path)
    args = parser.parse_args()

    stored_paths = [line.strip() for line in args.pck_paths.read_text(encoding="utf-8").splitlines()]
    archive_paths = [path.relative_to(args.root).as_posix() for path in args.root.rglob("*")]
    for path in archive_paths + stored_paths:
        if FORBIDDEN_PATH.search(path) or USER_MATERIAL.search(path):
            raise SystemExit(f"forbidden candidate path: {path}")

    secrets: list[bytes] = []
    for name, value in os.environ.items():
        if SECRET_NAME.search(name) and len(value) >= 8:
            secrets.append(value.encode("utf-8"))
    secrets.extend(KNOWN_SENTINELS)
    for path in args.root.rglob("*"):
        if not path.is_file():
            continue
        data = path.read_bytes()
        for secret in secrets:
            if secret and secret in data:
                raise SystemExit(f"secret value found in candidate file: {path.relative_to(args.root)}")

    print(f"candidate audit: {len(archive_paths)} archive paths, {len(stored_paths)} PCK paths, no protected material")


if __name__ == "__main__":
    main()
