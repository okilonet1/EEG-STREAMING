#!/usr/bin/env python3
import socket
import struct
import time
import numpy as np

# ---- Simulation parameters ----
HOST = '0.0.0.0'      # '127.0.0.1' for local-only; '0.0.0.0' allows LAN clients
PORT = 51244

NCH = 32              # number of EEG channels
FS = 500              # sampling rate (Hz)
BLOCK_POINTS = 25     # samples per packet (~50 ms)
MARKERS = 0

# ---- Sine waveform (signal-of-interest) ----
FREQ = 10.0           # Hz
AMP_NV = 50e3         # 50 µV in nV
PHASES = np.linspace(0, np.pi/2, NCH)

# ---- Mode flags ----
# Options: "sine", "sine_noise", "noise", "flat", "random"
MODE = "sine_noise"

# ---- Noise settings (tuned for your pre-cleaning) ----
LINE_FREQ = 60.0        # line noise freq (Hz)
LINE_AMP = 20e3         # ~20 µV line noise in nV

HARMONIC_FREQ = 120.0   # optional 2nd harmonic
HARMONIC_AMP = 5e3      # smaller amplitude

COMMON_DRIFT_FREQ = 0.2   # < 0.5 Hz so HPF should kill it
COMMON_DRIFT_AMP = 50e3  # big slow drift (in nV)

HF_NOISE_MIN = 70.0       # high-frequency noise band lower edge (Hz)
HF_NOISE_AMP = 5e3        # amplitude of HF noise in nV


def build_packet(block, n_block, markers=0):
    points, nch = block.shape
    subheader = struct.pack("<iii", n_block, points, markers)
    payload = block.tobytes(order="C")
    bytes_dat = len(payload)
    n_size = 12 + bytes_dat  # exclude 8-byte header
    n_type = 4               # 4 = Data packet (BrainVision)
    header = struct.pack("<ii", n_size, n_type)
    return header + subheader + payload


def generate_block(mode, block_points, fs, phases, t0):
    """
    Generate a synthetic EEG block [points x channels] in nV.
    t0 is the starting time of the block (in seconds) for continuous noise.
    """
    # Local time for this block (absolute, so slow drifts are continuous)
    t = t0 + np.arange(block_points) / fs  # shape [points]

    # ---------- Base signal ----------
    if mode == "sine":
        signal = np.sin(2 * np.pi * FREQ *
                        t[:, None] + phases[None, :]) * AMP_NV

    elif mode == "sine_noise":
        sine = np.sin(2 * np.pi * FREQ * t[:, None] + phases[None, :])
        # Per-channel Gaussian noise (broadband, low amplitude)
        noise = np.random.randn(block_points, NCH) * 1000.0  # ~±1 µV in nV
        signal = AMP_NV * sine + noise

    elif mode == "noise":
        # purely random (baseline) EEG-ish noise
        signal = np.random.randn(block_points, NCH) * 5000.0  # ±5 µV

    elif mode == "flat":
        signal = np.ones((block_points, NCH)) * 1000.0  # constant 1 µV

    elif mode == "random":
        step = np.random.randn(block_points, NCH) * 100.0
        signal = np.cumsum(step, axis=0)

    else:
        raise ValueError(f"Unknown MODE: {mode}")

    # ---------- Add structured noise your pipeline can remove ----------

    # 1) Common-mode low-frequency drift (same across channels)
    #    CAR + 0.5 Hz HPF should greatly reduce this.
    common_drift = COMMON_DRIFT_AMP * np.sin(2 * np.pi * COMMON_DRIFT_FREQ * t)
    common_drift = common_drift[:, None]  # [points x 1], broadcast to channels

    # 2) Line noise at 60 Hz + small 120 Hz harmonic
    line = LINE_AMP * np.sin(2 * np.pi * LINE_FREQ * t)
    harm = HARMONIC_AMP * np.sin(2 * np.pi * HARMONIC_FREQ * t)
    line = (line + harm)[:, None]  # broadcast across channels

    # 3) High-frequency noise > 45 Hz
    #    Simple way: random noise multiplied by a fast sinusoid to push it high.
    hf_carrier = np.sin(2 * np.pi * HF_NOISE_MIN * t)  # ~70 Hz
    hf_noise = (np.random.randn(block_points, NCH) *
                HF_NOISE_AMP * hf_carrier[:, None])

    # Total signal
    data = signal + common_drift + line + hf_noise

    return data.astype(np.int32)


def stream_to_client(conn):
    """Stream synthetic EEG to ONE connected client until disconnect."""
    n_block = 0
    # Track absolute time so drift/line noise are continuous across blocks
    t0 = 0.0

    while True:
        block = generate_block(MODE, BLOCK_POINTS, FS, PHASES, t0)
        packet = build_packet(block, n_block, MARKERS)
        conn.sendall(packet)
        n_block += 1

        # Advance time by block duration
        t0 += BLOCK_POINTS / FS
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
