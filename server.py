#!/usr/bin/env python3
import json
from http.server import HTTPServer, SimpleHTTPRequestHandler

ROOM_IDS = [
    "201","202","203","204","205","206","207","208","209","210",
    "211","212","213","214","215","세탁실",
    "216","217","218","219","220","221","222","223","224","225","226","227"
]

state = {
    "rooms": {id: {"occupancy": 0 if id == "세탁실" else 2} for id in ROOM_IDS},
    "requests": [],
    "messages": [],
}
_next_id = [0]

class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory="build/web", **kwargs)

    def do_OPTIONS(self):
        self.send_response(200)
        self._cors()
        self.end_headers()

    def do_GET(self):
        if self.path == "/api/state":
            self._json(state)
        else:
            super().do_GET()

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(length)) if length else {}

        if self.path == "/api/request":
            from_room = body["from"]   # currentPosition 을 받음
            to_room   = body["to"]
            name      = body.get("name", "")
            reason    = body.get("reason", "")
            # 같은 from_room 에서 이미 pending 이면 무시
            already = any(r["from_room"] == from_room and r["status"] == "pending" for r in state["requests"])
            if not already:
                req = {
                    "id": _next_id[0],
                    "from_room": from_room,
                    "to_room": to_room,
                    "status": "pending",
                    "name": name,
                    "reason": reason,
                }
                _next_id[0] += 1
                state["requests"].append(req)

        elif self.path == "/api/approve":
            for r in state["requests"]:
                if r["id"] == body["id"] and r["status"] == "pending":
                    from_occ = state["rooms"][r["from_room"]]["occupancy"]
                    to_occ   = state["rooms"][r["to_room"]]["occupancy"]
                    if from_occ > 0 and to_occ < 5:
                        state["rooms"][r["from_room"]]["occupancy"] -= 1
                        state["rooms"][r["to_room"]]["occupancy"]   += 1
                        r["status"] = "approved"
                    break

        elif self.path in ("/api/reject", "/api/cancel", "/api/delete_request"):
            state["requests"] = [r for r in state["requests"] if r["id"] != body["id"]]

        elif self.path == "/api/return":
            from_room = body["from"]   # currentPosition
            to_room   = body["to"]     # myRoom
            if state["rooms"][from_room]["occupancy"] > 0:
                state["rooms"][from_room]["occupancy"] -= 1
                state["rooms"][to_room]["occupancy"]   += 1

        elif self.path == "/api/chat":
            msg = {"id": _next_id[0], "room": body["room"], "msg": body["msg"]}
            _next_id[0] += 1
            state["messages"].append(msg)
            if len(state["messages"]) > 100:
                state["messages"] = state["messages"][-100:]

        self._json({"ok": True})

    def _json(self, data):
        body = json.dumps(data, ensure_ascii=False).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self._cors()
        self.end_headers()
        self.wfile.write(body)

    def _cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")

    def log_message(self, *args):
        pass  # 로그 끄기

class TabangServer(HTTPServer):
    def handle_error(self, request, client_address):
        import sys
        if sys.exc_info()[0] in (BrokenPipeError, ConnectionResetError):
            pass  # 브라우저가 연결 끊음 - 정상
        else:
            super().handle_error(request, client_address)

if __name__ == "__main__":
    server = TabangServer(("0.0.0.0", 8080), Handler)
    print("타방찬 서버 실행 중: http://localhost:8080")
    server.serve_forever()
