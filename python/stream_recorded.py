#!/usr/bin/env python3
import socket
import struct
import time
import numpy as np

# ---- Settings ----
HOST = '0.0.0.0'
PORT = 51244
FS = 500                 # sampling rate (Hz)
BLOCK_POINTS = 25        # samples per packet (~50 ms)
MARKERS = 0

FNAME = "data/EEG_export.txt"


def load_eeg(fname):
    """Load EEG data from text file and return data in nV as int32."""
    data = np.loadtxt(fname)

    # Heuristic: first column might be time if it's strictly increasing
    col0 = data[: min(100, data.shape[0]), 0]
    diffs = np.diff(col0)
    # time-like if positive and small-ish
    if np.all(diffs > 0) and np.mean(diffs) < 0.1:
        data = data[:, 1:]

    nSamples, nCh = data.shape
    print(f"[Replay] Loaded {nSamples} samples × {nCh} channels from {fname}")

    # µV -> nV (int32)
    data_nv = (data * 1000).astype(np.int32)
    return data_nv, nSamples, nCh


def build_packet(block, nBlock, markers=0):
    """
    Build BrainVision-style RDA data packet:
    header (8 bytes) + subheader (12 bytes) + payload
    """
    block_points, nCh = block.shape

    subheader = struct.pack("<iii", nBlock, block_points, markers)
    payload = block.tobytes(order="C")
    bytesDat = len(payload)
    nSize = 12 + bytesDat          # exclude 8-byte main header
    nType = 4                      # 4 = Data packet
    header = struct.pack("<ii", nSize, nType)
    return header + subheader + payload


def stream_to_client(conn, data_nv, nSamples, fs, block_points):
    """Main loop streaming to ONE connected client."""
    start = 0
    nBlock = 0

    while True:
        end = start + block_points
        if end > nSamples:
            print("[Replay] Reached end of file — restarting.")
            start = 0
            end = block_points

        block = data_nv[start:end, :]  # [points x channels]
        start = end

        packet = build_packet(block, nBlock)
        conn.sendall(packet)
        nBlock += 1

        # Real-time pacing
        time.sleep(block_points / fs)


def main():
    data_nv, nSamples, nCh = load_eeg(FNAME)

    print(f"[Replay] Starting EEG stream server on {HOST}:{PORT}")
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((HOST, PORT))
    srv.listen(1)
    print("[Replay] Waiting for client connections...")

    try:
        while True:
            conn, addr = srv.accept()
            print(f"[Replay] Client connected from {addr}")

            try:
                stream_to_client(conn, data_nv, nSamples, FS, BLOCK_POINTS)
            except (BrokenPipeError, ConnectionResetError, OSError) as e:
                print(
                    f"[Replay] Client disconnected ({e}). Waiting for new client...")
            finally:
                conn.close()

    except KeyboardInterrupt:
        print("\n[Replay] Interrupted by user, shutting down.")
    finally:
        srv.close()
        print("[Replay] Server closed.")


if __name__ == "__main__":
    main()
