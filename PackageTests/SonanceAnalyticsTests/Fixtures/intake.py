"""Real loopback HTTP intake with SQLite uniqueness, used by native integration tests."""
import json
import sqlite3
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

db = sqlite3.connect(":memory:", check_same_thread=False)
db.execute("create table events (id text primary key, body text not null)")
lock = threading.Lock()
attempts = 0


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def respond(self, code, payload):
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def do_GET(self):
        with lock:
            rows = [json.loads(row[0]) for row in db.execute("select body from events order by rowid")]
        self.respond(200, {"events": rows, "attempts": attempts})

    def do_POST(self):
        global attempts
        body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        if self.headers.get("apikey") != "sb_publishable_integration_test_loopback_only":
            self.respond(401, {"code": "unauthorized"})
            return
        try:
            row = json.loads(body)
        except ValueError:
            self.respond(400, {"code": "invalid_json"})
            return
        with lock:
            attempts += 1
            attempt = attempts
        if self.path == "/fail-once" and attempt == 1:
            self.respond(503, {"code": "temporarily_unavailable"})
            return
        if self.path == "/redirect":
            self.send_response(307)
            self.send_header("Location", "/events")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if self.path == "/slow":
            time.sleep(1)
        try:
            with lock:
                db.execute("insert into events values (?, ?)", (row["event_id"], json.dumps(row)))
                db.commit()
        except sqlite3.IntegrityError:
            self.respond(409, {"code": "23505"})
            return
        self.respond(409 if self.path == "/already-delivered" else 201,
                     {"code": "23505"} if self.path == "/already-delivered" else {})


server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
Path(sys.argv[1]).write_text(str(server.server_address[1]))
server.serve_forever(poll_interval=0.05)
