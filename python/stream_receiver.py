# # # import socket
# # # import struct
# # # import numpy as np

# # # TCP_IP = '127.0.0.1'
# # # TCP_PORT = 8000

# # # sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
# # # sock.bind((TCP_IP, TCP_PORT))
# # # sock.listen(1)
# # # print(f"Listening on {TCP_IP}:{TCP_PORT}...")

# # # conn, addr = sock.accept()
# # # print("Connected by", addr)

# # # while True:
# # #     data = conn.recv(4096)
# # #     if not data:
# # #         break

# # #     arr = np.frombuffer(data, dtype=np.float32)
# # #     print("Received", len(data), "bytes", end='; '

# # #           )

# # #     print(data)
# # #     print("Received", arr.shape, "values")
# # # python_tcp_server_read_float32.py
# # import socket
# # import struct
# # import time

# # HOST = "0.0.0.0"
# # PORT = 51244


# # def recvn(sock, n):
# #     data = b""
# #     while len(data) < n:
# #         chunk = sock.recv(n - len(data))
# #         if not chunk:
# #             raise ConnectionError("Socket closed")
# #         data += chunk
# #     return data


# # srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
# # srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
# # srv.bind((HOST, PORT))
# # srv.listen(1)

# # print(f"Python server listening on {HOST}:{PORT} ...")
# # conn, addr = srv.accept()
# # print("Client connected:", addr)

# # count = 0
# # t0 = time.time()

# # while True:
# #     b = recvn(conn, 4)
# #     x = struct.unpack("<f", b)[0]
# #     count += 1
# #     if count % 200 == 0:
# #         rate = count / (time.time() - t0)
# #         print(f"x={x:.4f} | recv_rate≈{rate:.1f} Hz")


# import socket
# import time

# HOST = "0.0.0.0"
# PORT = 51244

# sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
# sock.bind((HOST, PORT))
# sock.listen(1)

# print(f"[receiver] Listening on {HOST}:{PORT} ...")
# conn, addr = sock.accept()
# print(f"[receiver] Connected from {addr}")

# buf = b""
# count = 0
# t0 = time.time()

# while True:
#     data = conn.recv(4096)
#     if not data:
#         break

#     buf += data

#     while b"\n" in buf:
#         line, buf = buf.split(b"\n", 1)
#         count += 1

#     if time.time() - t0 >= 1.0:
#         print(f"[receiver] ~{count} msgs/sec")
#         count = 0
#         t0 = time.time()


# python_tcp_server_read_float32.py
import socket
import struct
import time

HOST = "0.0.0.0"
PORT = 9000


def recvn(sock, n):
    data = b""
    while len(data) < n:
        chunk = sock.recv(n - len(data))
        if not chunk:
            raise ConnectionError("Socket closed")
        data += chunk
    return data


srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind((HOST, PORT))
srv.listen(1)

print(f"Python server listening on {HOST}:{PORT} ...")
conn, addr = srv.accept()
print("Client connected:", addr)

count = 0
t0 = time.time()

while True:
    b = recvn(conn, 4)
    x = struct.unpack("<f", b)[0]
    count += 1
    if count % 200 == 0:
        rate = count / (time.time() - t0)
        print(f"x={x:.4f} | recv_rate≈{rate:.1f} Hz")
