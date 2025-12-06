#!/usr/bin/env python3
import socket
import struct
import time
import numpy as np

# ---- Settings ----
HOST = '127.0.0.1'
PORT = 51244
FS = 500                 # sampling rate (Hz)
BLOCK_POINTS = 25        # samples per packet (~50 ms)
MARKERS = 0

# ---- Load EEG text file ----
# Expected format: [nSamples x nChannels] (or with time column first)
fname = "data/EEG_export.txt"

data = np.loadtxt(fname)

# If first column is time, drop it
if np.all(np.diff(data[:100, 0]) < 0.01):  # heuristic check for time column
    data = data[:, 1:]

nSamples, NCH = data.shape
print(f"[Replay] Loaded {nSamples} samples × {NCH} channels from {fname}")

# Convert from µV to nV (BrainVision RDA convention)
data_nv = (data * 1000).astype(np.int32)

# ---- Setup TCP server ----
print(f"[Replay] Starting EEG stream on {HOST}:{PORT}")
srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind((HOST, PORT))
srv.listen(1)
conn, addr = srv.accept()
print(f"[Replay] Client connected from {addr}")

# ---- Stream loop ----
nBlock = 0
start = 0

try:
    while True:
        # Select block
        end = start + BLOCK_POINTS
        if end > nSamples:
            print("[Replay] Reached end of file — restarting.")
            start = 0
            end = BLOCK_POINTS
        block = data_nv[start:end, :]  # [points x channels]
        start = end

        # ---- Packet structure ----
        subheader = struct.pack("<iii", nBlock, BLOCK_POINTS, MARKERS)
        payload = block.tobytes(order="C")
        bytesDat = len(payload)
        nSize = 12 + bytesDat          # exclude 8-byte main header
        nType = 4                      # 4 = Data packet
        header = struct.pack("<ii", nSize, nType)
        packet = header + subheader + payload

        # Send
        conn.sendall(packet)
        nBlock += 1

        # Simulate real-time pacing
        time.sleep(BLOCK_POINTS / FS)

except KeyboardInterrupt:
    print("\n[Replay] Interrupted — closing stream.")
finally:
    conn.close()
    srv.close()
    print("[Replay] Done.")
