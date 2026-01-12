import socket

s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.connect(("192.168.50.216", 6700))

s.sendall(b"GETSTATUS\n")
print(s.recv(1024).decode())

s.sendall(b"START\n")
print(s.recv(1024).decode())

s.sendall(b"MARKER TestMarker\n")
print(s.recv(1024).decode())

s.sendall(b"STOP\n")
print(s.recv(1024).decode())

s.close()
