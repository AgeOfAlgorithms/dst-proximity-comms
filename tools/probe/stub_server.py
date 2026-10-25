"""A stand-in for Koetama's HTTP connector, for the QueryServer probe (tools/probe/proxcomms_probe).

Listens on 127.0.0.1:<port> (default 47170), logs every request byte for byte (request line, headers, body length,
whether Content-Length matches), and answers JSON. Paths steer it:
  /hold/<seconds>   wait that long before answering (concurrency and long-poll tests)
  /status/<code>    answer with that status code
  /big/<kb>         answer a body of that many KB (with UTF-8 in it)
  /                 GET: Koetama's "is it there" answer; POST: echo the body's length and its first bytes

Run: python tools/probe/stub_server.py [port] [log file]
"""
import json
import socket
import sys
import threading
import time

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 47170
LOG = sys.argv[2] if len(sys.argv) > 2 else None
lock = threading.Lock()
t0 = time.time()


def log(msg):
    line = "%8.3f %s" % (time.time() - t0, msg)
    with lock:
        print(line, flush=True)
        if LOG:
            with open(LOG, "a", encoding="utf-8") as f:
                f.write(line + "\n")


def read_request(conn):
    data = b""
    while b"\r\n\r\n" not in data:
        chunk = conn.recv(65536)
        if not chunk:
            return None, None, None
        data += chunk
    head, _, rest = data.partition(b"\r\n\r\n")
    lines = head.decode("latin-1").split("\r\n")
    headers = {}
    for h in lines[1:]:
        k, _, v = h.partition(":")
        headers[k.strip().lower()] = v.strip()
    body = rest
    if "content-length" in headers:
        n = int(headers["content-length"])
        while len(body) < n:
            chunk = conn.recv(65536)
            if not chunk:
                break
            body += chunk
    elif headers.get("transfer-encoding", "").lower() == "chunked":
        # read until the terminating chunk, keep it raw (logged as chunked)
        while not body.endswith(b"0\r\n\r\n"):
            chunk = conn.recv(65536)
            if not chunk:
                break
            body += chunk
    return lines[0], headers, body


def answer(conn, code, obj_or_bytes, reason="OK"):
    body = obj_or_bytes if isinstance(obj_or_bytes, bytes) else json.dumps(obj_or_bytes, ensure_ascii=False).encode()
    conn.sendall(("HTTP/1.1 %d %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n"
                  % (code, reason, len(body))).encode() + body)


def handle(conn, addr):
    try:
        conn.settimeout(10)
        line, headers, body = read_request(conn)
        if line is None:
            log("conn %s closed before a request" % (addr,))
            return
        cl = headers.get("content-length")
        log("REQ %s | headers %s | body %d bytes | content-length %s%s" % (
            line, json.dumps(headers), len(body), cl,
            "" if cl is None or int(cl) == len(body) else " MISMATCH"))
        if body:
            log("    body starts: %r" % body[:160])
        path = line.split(" ")[1] if " " in line else "/"
        if path.startswith("/hold/"):
            secs = float(path.split("/")[2])
            time.sleep(secs)
            answer(conn, 200, {"held": secs, "got": len(body)})
        elif path.startswith("/status/"):
            code = int(path.split("/")[2])
            answer(conn, code, {"error": "status %d" % code}, "X")
        elif path.startswith("/big/"):
            kb = int(path.split("/")[2])
            unit = "héllo こんにちは "  # 7 + 16 bytes
            text = (unit * (kb * 1024 // len(unit.encode()) + 1))
            answer(conn, 200, {"text": text, "bytes": len(text.encode())})
        elif line.startswith("GET"):
            answer(conn, 200, {"app": "Koetama", "version": "stub", "protocol": 2, "game": "dont-starve-together-proximity-comms"})
        else:
            answer(conn, 200, {"objects": [{"type": "hello", "app": "Koetama", "version": "stub", "protocol": 2,
                                            "features": ["speech", "voices", "rooms", "translate"]}],
                               "first": 1, "last": 1, "got": len(body),
                               "echo": body[:40].decode("utf-8", "replace")})
    except Exception as e:  # noqa: BLE001 - a probe logs everything
        log("ERROR %r" % e)
    finally:
        conn.close()


def main():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("127.0.0.1", PORT))
    s.listen(32)
    log("listening on 127.0.0.1:%d" % PORT)
    while True:
        conn, addr = s.accept()
        threading.Thread(target=handle, args=(conn, addr), daemon=True).start()


if __name__ == "__main__":
    main()
