#!/usr/bin/env python3
import http.server
import json
import os
import sys
import urllib.parse


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        path = urllib.parse.urlparse(self.path).path
        if path != "/v1/models":
            self.send_error(404)
            return

        expected = os.environ.get("QUILLCODE_DOCTOR_EXPECTED_TOKEN", "")
        if self.headers.get("Authorization") != f"Bearer {expected}":
            self.send_error(401)
            return
        user_agent = self.headers.get("User-Agent", "")
        if not user_agent.startswith("QuillCode/") or not user_agent.endswith(" doctor"):
            self.send_error(400)
            return

        body = json.dumps({"data": []}).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, _format, *args):
        pass


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: doctor-http-server.py PORT_FILE")
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    with open(sys.argv[1], "w", encoding="utf-8") as handle:
        handle.write(str(server.server_address[1]))
        handle.flush()
        os.fsync(handle.fileno())
    server.serve_forever()


if __name__ == "__main__":
    main()
