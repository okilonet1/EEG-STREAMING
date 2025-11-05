#!/usr/bin/env python3
import socket
import struct
import time
import numpy as np

# ---- Simulation parameters ----
HOST = '127.0.0.1'
PORT = 51244
NCH = 32              # number of EEG channels
FS = 500              # sampling rate (Hz)
BLOCK_POINTS = 25     # samples per packet (~50 ms)
MARKERS = 0

print(f"[Simulator] Starting EEG stream on {HOST}:{PORT}")
srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind((HOST, PORT))
srv.listen(1)
conn, addr = srv.accept()
print(f"[Simulator] Client connected from {addr}")

nBlock = 0
freq = 10.0           # Hz sine wave
amp = 50e3           # 50 µV in nV
phase = np.linspace(0, np.pi/2, NCH)  # slight phase shift per channel

try:
    while True:
        t = np.arange(BLOCK_POINTS) / FS  # time vector (s)

        # simple sine wave with random noise (nV)
        data = 1000 * np.sin(2*np.pi*10*t)[None, :] + \
            np.random.randn(NCH, BLOCK_POINTS)*100
        # data = data.astype(np.int32).T  # shape [points, channels]

        # Each channel: sine with different phase + small random noise
        # sine = np.sin(2 * np.pi * freq * t[:, None] + phase[None, :])
        # noise = np.random.randn(BLOCK_POINTS, NCH) * 1000.0  # ±1 µV noise
        # data = amp * sine + noise                            # in nV
        data_i32 = data.astype(np.int32)

        # ---- RDA-like packet ----
        subheader = struct.pack("<iii", nBlock, BLOCK_POINTS, MARKERS)
        payload = data_i32.tobytes(order="C")
        bytesDat = len(payload)
        nSize = 12 + bytesDat         # exclude 8B header
        nType = 4                     # 4 = Data packet
        header = struct.pack("<ii", nSize, nType)
        packet = header + subheader + payload

        # Send and wait real-time
        conn.sendall(packet)
        nBlock += 1
        time.sleep(BLOCK_POINTS / FS)

except KeyboardInterrupt:
    print("\n[Simulator] Closing...")
finally:
    conn.close()
    srv.close()
