#!/usr/bin/env python3
"""Loopback-only generated-media fixture with byte ranges. No external media or credentials."""
import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import re

parser = argparse.ArgumentParser()
parser.add_argument("directory", type=Path)
parser.add_argument("--port", type=int, default=18764)
args = parser.parse_args()
types = {"cd.flac": "audio/flac", "hires.flac": "audio/flac",
         "alac.m4a": "audio/mp4", "alac-fast.m4a": "audio/mp4"}


class Media(BaseHTTPRequestHandler):
    def do_HEAD(self):
        self.media(False)

    def do_GET(self):
        self.media(True)

    def media(self, body):
        name = self.path.removeprefix("/")
        if name not in types or not (args.directory / name).is_file():
            self.send_error(404)
            return
        path = args.directory / name
        length = path.stat().st_size
        start, end, status = 0, length - 1, 200
        requested = self.headers.get("Range")
        if requested:
            match = re.fullmatch(r"bytes=(\d*)-(\d*)", requested)
            valid = match and any(match.groups())
            if valid:
                left, right = match.groups()
                if left:
                    start = int(left)
                    end = min(int(right), length - 1) if right else length - 1
                else:
                    start = max(0, length - int(right))
                valid = 0 <= start <= end < length
            if not valid:
                self.send_response(416)
                self.send_header("Content-Range", f"bytes */{length}")
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            status = 206
        self.send_response(status)
        self.send_header("Content-Type", types[name])
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(end - start + 1))
        if status == 206:
            self.send_header("Content-Range", f"bytes {start}-{end}/{length}")
        self.end_headers()
        if body:
            try:
                with path.open("rb") as stream:
                    stream.seek(start)
                    remaining = end - start + 1
                    while remaining:
                        block = stream.read(min(65536, remaining))
                        if not block:
                            break
                        self.wfile.write(block)
                        remaining -= len(block)
            except (BrokenPipeError, ConnectionResetError):
                pass


print(f"Generated fixtures at http://localhost:{args.port}/", flush=True)
ThreadingHTTPServer(("127.0.0.1", args.port), Media).serve_forever()
