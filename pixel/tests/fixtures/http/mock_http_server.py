#!/usr/bin/env python3
"""Deterministic local server for the M4 HTTP contract tests."""

import json
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


class Handler(BaseHTTPRequestHandler):
    retry_count = 0
    comfy_prompt = {}
    comfy_interrupts = 0

    def do_GET(self) -> None:  # noqa: N802 - stdlib callback name
        if self.path == "/openai-model":
            self._json(200, {"id": "gpt-image-2", "object": "model"})
        elif self.path == "/system_stats":
            self._json(200, {"system": {"os": "fixture"}, "devices": []})
        elif self.path == "/last-comfy-prompt":
            self._json(200, Handler.comfy_prompt)
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
        content_length = int(self.headers.get("Content-Length", "0"))
        request_body = {}
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
            pixel = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
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
                "background": "transparent",
                "output_format": "png",
                "quality": "low",
                "size": request_body.get("size", "1024x1024"),
                "data": [{"b64_json": pixel}] * image_count,
                "usage": {"total_tokens": 42},
            })
        elif self.path == "/auth":
            self._json(401, {"error": "bad credentials"})
        elif self.path == "/rate-limit":
            self._json(429, {"error": "slow down"})
        elif self.path == "/retry-three":
            Handler.retry_count += 1
            if Handler.retry_count <= 3:
                self._json(429, {"error": "retry", "attempt": Handler.retry_count})
            else:
                self._json(200, {"ok": True, "attempt": Handler.retry_count})
        elif self.path == "/timeout":
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

    def _json(self, status: int, body: dict) -> None:
        payload = json.dumps(body).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        try:
            self.wfile.write(payload)
        except BrokenPipeError:
            pass


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: mock_http_server.py PORT_FILE")
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    Path(sys.argv[1]).write_text(str(server.server_port), encoding="utf-8")
    server.serve_forever()


if __name__ == "__main__":
    main()
