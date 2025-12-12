import socket
import struct
import numpy as np

TCP_IP = '127.0.0.1'
TCP_PORT = 268

sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.bind((TCP_IP, TCP_PORT))
sock.listen(1)
print(f"Listening on {TCP_IP}:{TCP_PORT}...")

conn, addr = sock.accept()
print("Connected by", addr)

while True:
    data = conn.recv(4096)
    if not data:
        break

    arr = np.frombuffer(data, dtype=np.float32)
    print("Received", arr.shape, "values")
