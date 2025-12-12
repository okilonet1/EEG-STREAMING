#!/usr/bin/env python3
import socket
import struct
import time
import numpy as np

# ---- Simulation parameters ----
HOST = '0.0.0.0'      # use '127.0.0.1' for local-only; '0.0.0.0' allows LAN clients
PORT = 51244

NCH = 32              # number of EEG channels
FS = 500              # sampling rate (Hz)
BLOCK_POINTS = 25     # samples per packet (~50 ms)
MARKERS = 0

# ---- Sine waveform settings ----
FREQ = 10.0           # Hz
AMP_NV = 50e3         # 50 µV in nV
PHASES = np.linspace(0, np.pi/2, NCH)

# ---- Mode flags ----
# Options: "sine", "sine_noise", "noise", "flat", "random"
MODE = "sine_noise"


def build_packet(block, n_block, markers=0):
    points, nch = block.shape
    subheader = struct.pack("<iii", n_block, points, markers)
    payload = block.tobytes(order="C")
    bytes_dat = len(payload)
    n_size = 12 + bytes_dat  # exclude 8-byte header
    n_type = 4               # 4 = Data packet (BrainVision)
    header = struct.pack("<ii", n_size, n_type)
    return header + subheader + payload


def generate_block(mode, block_points, fs, phases):
    """Generate a synthetic EEG block [points x channels] in nV."""
    t = np.arange(block_points) / fs  # [points]

    if mode == "sine":
        data = np.sin(2 * np.pi * FREQ * t[:, None] + phases[None, :]) * AMP_NV

    elif mode == "sine_noise":
        sine = np.sin(2 * np.pi * FREQ * t[:, None] + phases[None, :])
        noise = np.random.randn(block_points, NCH) * \
            1000.0  # ±1 µV noise in nV
        data = (AMP_NV * sine) + noise

    elif mode == "noise":
        data = np.random.randn(block_points, NCH) * 5000.0  # ±5 µV noise

    elif mode == "flat":
        data = np.ones((block_points, NCH)) * 1000.0  # constant 1 µV

    elif mode == "random":
        # slow random walk (ECG-like drift)
        step = np.random.randn(block_points, NCH) * 100.0
        data = np.cumsum(step, axis=0)

    else:
        raise ValueError(f"Unknown MODE: {mode}")

    return data.astype(np.int32)


def stream_to_client(conn):
    """Stream synthetic EEG to ONE connected client until disconnect."""
    n_block = 0

    while True:
        block = generate_block(MODE, BLOCK_POINTS, FS, PHASES)
        packet = build_packet(block, n_block, MARKERS)
        conn.sendall(packet)
        n_block += 1
        time.sleep(BLOCK_POINTS / FS)


def main():
    print(f"[Simulator] Starting EEG stream server on {HOST}:{PORT}")
    print(f"[Simulator] Mode: {MODE}")

    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((HOST, PORT))
    srv.listen(1)

    print("[Simulator] Waiting for client connections...")

    try:
        while True:
            conn, addr = srv.accept()
            print(f"[Simulator] Client connected from {addr}")

            try:
                stream_to_client(conn)
            except (BrokenPipeError, ConnectionResetError, OSError) as e:
                print(
                    f"[Simulator] Client disconnected ({e}). Restarting accept loop...")
            finally:
                conn.close()

    except KeyboardInterrupt:
        print("\n[Simulator] Stopping server...")

    finally:
        srv.close()
        print("[Simulator] Server closed.")


if __name__ == "__main__":
    main()
