import json
import socket
import threading
import time


def read(conn, addr):
    try:
        while True:
            msg = conn.recv(1024).decode()
            if msg != "":
                print("[INFO]\tMessage:", msg)
    except ConnectionError:
        print("[INFO]\tread lost connection to ", addr)


def write(conn, addr):
    try:
        while True:
            conn.send(json.dumps({ "cmd": 'ACCOUNT' }).encode())
            time.sleep(3)
    except ConnectionError:
        print("[INFO]\twrite lost connection to ", addr)


server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.bind(("127.0.0.1", 8888))
server.listen(10)

while True:
    connection, address = server.accept()
    print("[INFO]\tConnection established with: ", address)

    thread_read = threading.Thread(target=read, args=(connection, address))
    thread_read.start()

    thread_write = threading.Thread(target=write, args=(connection, address))
    thread_write.start()

    time.sleep(1)
