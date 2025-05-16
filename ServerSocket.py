import json
import socket
import threading
import time


def read(conn, addr):
    try:
        while True:
            msg = conn.recv(1024).decode()
            if msg:
                print(f"[INFO] Message from {addr}: {msg}")
            else:
                break
    except Exception as e:
        print(f"[ERROR] read from {addr} -> {e}")
    finally:
        conn.close()
        print(f"[INFO] Connection closed with {addr}")


def write(conn, addr):
    try:
        while True:
            payload = { "cmd": "ACCOUNT" }
            conn.send(json.dumps(payload).encode())
            time.sleep(3)
    except Exception as e:
        print(f"[ERROR] write to {addr} -> {e}")
    finally:
        conn.close()


def start_server():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.bind(("0.0.0.0", 8888))  # accessible from Docker
    server.listen(10)
    print("[INFO] Server is listening on port 8888", server.getsockname())

    while True:
        conn, addr = server.accept()
        print(f"[INFO] Connection established with {addr}")

        thread_r = threading.Thread(target=read, args=(conn, addr))
        thread_w = threading.Thread(target=write, args=(conn, addr))

        thread_r.daemon = True
        thread_w.daemon = True

        thread_r.start()
        thread_w.start()


if __name__ == "__main__":
    start_server()
