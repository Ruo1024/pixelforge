#!/usr/bin/env python3
"""Deterministic local server for the M4 HTTP contract tests."""

import json
import hashlib
import base64
import re
import struct
import sys
import time
import socket
import zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse


def _solid_png_base64(width: int, height: int) -> str:
    """Return a deterministic opaque RGBA PNG at the requested provider size."""

    def chunk(kind: bytes, data: bytes) -> bytes:
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    width = max(1, width)
    height = max(1, height)
    row = b"\x00" + (b"\x4f\x6f\x8f\xff" * width)
    payload = b"\x89PNG\r\n\x1a\n"
    payload += chunk("IHDR".encode(), struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    payload += chunk("IDAT".encode(), zlib.compress(row * height, 9))
    payload += chunk("IEND".encode(), b"")
    return base64.b64encode(payload).decode()


class Handler(BaseHTTPRequestHandler):
    retry_count = 0
    safe_retry_count = 0
    credential_sentinel_received = False
    request_counts = {}
    comfy_prompt = {}
    comfy_interrupts = 0
    openai_edit = {}

    def do_GET(self) -> None:  # noqa: N802 - stdlib callback name
        parsed_path = urlparse(self.path)
        if parsed_path.path == "/request-count":
            target = parse_qs(parsed_path.query).get("path", [""])[0]
            self._json(200, {"count": Handler.request_counts.get(target, 0)})
        elif self.path == "/retry-three":
            Handler.retry_count += 1
            if Handler.retry_count <= 3:
                self._json(429, {"error": "retry", "attempt": Handler.retry_count})
            else:
                self._json(200, {"ok": True, "attempt": Handler.retry_count})
        elif self.path == "/safe-retry":
            Handler.safe_retry_count += 1
            if Handler.safe_retry_count <= 2:
                self._json(
                    429,
                    {"error": "retry", "attempt": Handler.safe_retry_count},
                    {"Retry-After": "3600"},
                )
            else:
                self._json(200, {"ok": True, "attempt": Handler.safe_retry_count})
        elif self.path == "/credential-sentinel-status":
            self._json(200, {"received": Handler.credential_sentinel_received})
        elif self.path == "/openai-model":
            self._json(200, {"id": "gpt-image-2", "object": "model"})
        elif self.path == "/system_stats":
            self._json(200, {"system": {"os": "fixture"}, "devices": []})
        elif self.path == "/last-comfy-prompt":
            self._json(200, Handler.comfy_prompt)
        elif self.path == "/last-openai-edit":
            self._json(200, Handler.openai_edit)
        elif self.path.startswith("/history/"):
            prompt_id = self.path.rsplit("/", 1)[-1]
            if prompt_id == "comfy-slow":
                self._json(200, {})
            else:
                self._json(200, {prompt_id: {"outputs": {"9": {"images": [
                    {"filename": "fixture.png", "subfolder": "", "type": "output"}
                ]}}}})
        elif self.path.startswith("/view?"):
            payload = __import__("base64").b64decode(
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
            )
            self.send_response(200)
            self.send_header("Content-Type", "image/png")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
        else:
            self._json(404, {"error": {"message": "missing"}})

    def do_POST(self) -> None:  # noqa: N802 - stdlib callback name
        request_path = urlparse(self.path).path
        Handler.request_counts[request_path] = Handler.request_counts.get(request_path, 0) + 1
        content_length = int(self.headers.get("Content-Length", "0"))
        request_body = {}
        raw_body = b""
        if content_length:
            raw_body = self.rfile.read(content_length)
            try:
                request_body = json.loads(raw_body)
            except (json.JSONDecodeError, UnicodeDecodeError):
                request_body = {}

        if self.path == "/success":
            self._json(200, {"ok": True})
        elif self.path == "/prompt":
            Handler.comfy_prompt = request_body
            prompt_text = json.dumps(request_body)
            self._json(200, {
                "prompt_id": "comfy-slow" if "slow generation" in prompt_text else "comfy-prompt",
                "number": 1,
                "node_errors": {},
            })
        elif self.path == "/interrupt":
            Handler.comfy_interrupts += 1
            self._json(200, {"ok": True, "interrupts": Handler.comfy_interrupts})
        elif self.path == "/upload/image":
            self._json(200, {"name": "uploaded.png", "subfolder": "", "type": "input"})
        elif self.path in {"/retrodiffusion-success", "/retrodiffusion-slow"}:
            if self.path == "/retrodiffusion-slow":
                time.sleep(0.3)
            pixel = _solid_png_base64(
                int(request_body.get("width", 1)), int(request_body.get("height", 1))
            )
            image_count = max(1, min(4, int(request_body.get("num_images", 1))))
            self._json(200, {
                "created_at": 1783780000,
                "balance_cost": 0.25 * image_count,
                "base64_images": [pixel] * image_count,
                "model": "rd_plus",
                "remaining_balance": 99.75,
            })
        elif self.path == "/openai-image-success":
            pixel = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
            image_count = max(1, min(4, int(request_body.get("n", 1))))
            self._json(200, {
                "created": 1783770000,
                "background": request_body.get("background", "opaque"),
                "output_format": "png",
                "quality": "low",
                "size": request_body.get("size", "1024x1024"),
                "data": [{"b64_json": pixel}] * image_count,
                "usage": {"total_tokens": 42},
            })
        elif self.path == "/openai-image-edit":
            fields, reference_hashes = self._multipart_fields(raw_body)
            Handler.openai_edit = {
                "fields": fields,
                "reference_sha256s": reference_hashes,
            }
            pixel = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
            image_count = max(1, min(4, int(fields.get("n", "1"))))
            self._json(200, {
                "created": 1783770000,
                "background": fields.get("background", "opaque"),
                "output_format": fields.get("output_format", "png"),
                "quality": fields.get("quality", "low"),
                "size": fields.get("size", "1024x1024"),
                "data": [{"b64_json": pixel}] * image_count,
                "usage": {
                    "total_tokens": 84,
                    "fixture_reference_sha256s": reference_hashes,
                },
            })
        elif self.path == "/auth":
            self._json(401, {"error": "bad credentials"})
        elif self.path in {"/rate-limit", "/post-rate-limit"}:
            self._json(429, {"error": "slow down"})
        elif self.path in {"/server-error", "/post-server-error"}:
            self._json(503, {"error": "temporary failure"})
        elif self.path == "/network-drop":
            self.connection.shutdown(socket.SHUT_RDWR)
            self.connection.close()
        elif self.path.startswith("/credential-sentinel?"):
            sentinel = "PF_B7_CREDENTIAL_SENTINEL_7B1E9C42"
            Handler.credential_sentinel_received = self.headers.get("X-RD-Token") == sentinel
            self._json(401, {"error": {"code": sentinel, "message": sentinel}})
        elif self.path == "/credential-sentinel-success":
            sentinel = "PF_B7_CREDENTIAL_SENTINEL_7B1E9C42"
            Handler.credential_sentinel_received = self.headers.get("X-RD-Token") == sentinel
            self._json(200, {"echo": sentinel})
        elif self.path == "/retry-three":
            Handler.retry_count += 1
            if Handler.retry_count <= 3:
                self._json(429, {"error": "retry", "attempt": Handler.retry_count})
            else:
                self._json(200, {"ok": True, "attempt": Handler.retry_count})
        elif self.path in {"/timeout", "/post-timeout"}:
            time.sleep(0.3)
            self._json(200, {"ok": True})
        elif self.path == "/malformed":
            payload = b"{not-json"
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
        else:
            self._json(404, {"error": "missing"})

    def log_message(self, _format: str, *_args: object) -> None:
        return

    def _json(self, status: int, body: dict, headers=None) -> None:
        payload = json.dumps(body).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        for name, value in (headers or {}).items():
            self.send_header(name, value)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        try:
            self.wfile.write(payload)
        except BrokenPipeError:
            pass

    def _multipart_fields(self, body: bytes) -> tuple[dict[str, str], list[str]]:
        content_type = self.headers.get("Content-Type", "")
        boundary_match = re.search(r"boundary=([^;]+)", content_type)
        if not boundary_match:
            return {}, []
        boundary = ("--" + boundary_match.group(1)).encode("ascii")
        fields: dict[str, str] = {}
        reference_hashes: list[str] = []
        for part in body.split(boundary):
            part = part.strip(b"\r\n-")
            if not part or b"\r\n\r\n" not in part:
                continue
            header_bytes, value = part.split(b"\r\n\r\n", 1)
            value = value.removesuffix(b"\r\n")
            headers = header_bytes.decode("latin-1")
            name_match = re.search(r'name="([^"]+)"', headers)
            if not name_match:
                continue
            if name_match.group(1) == "image[]":
                reference_hashes.append(hashlib.sha256(value).hexdigest())
            else:
                fields[name_match.group(1)] = value.decode("utf-8")
        return fields, reference_hashes


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: mock_http_server.py PORT_FILE")
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    Path(sys.argv[1]).write_text(str(server.server_port), encoding="utf-8")
    server.serve_forever()


if __name__ == "__main__":
    main()
