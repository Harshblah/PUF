#!/usr/bin/env python3
"""
collect_crp.py – Collect multiple PUF challenge-response pair (CRP) runs
                 from the Basys3 board and save them directly to Outputs/

Usage:
    python collect_crp.py <PORT> [NUM_RUNS]

Example:
    python collect_crp.py COM3 50
"""

import serial
import sys
import os
import time

# ── Configuration & Constants ────────────────────────────────────────────────
BAUD_RATE        = 921_600
HEADER           = bytes([0xAA, 0x55, 0xAA, 0x55])
TOTAL_CHALLENGES = 1 << 20                  # 1,048,576
TOTAL_BYTES      = TOTAL_CHALLENGES // 8     # 131,072 bytes

HDR_TIMEOUT_S    = 300
DATA_TIMEOUT_S   = 60

OUTPUT_DIR       = r"C:\Users\DELL\Desktop\Project_ECE\RO_PUF\RO_puf\Outputs"


def find_header(ser: serial.Serial) -> bool:
    """Wait for sync header (0xAA 0x55 0xAA 0x55)."""
    buf = bytearray()
    deadline = time.time() + HDR_TIMEOUT_S
    while time.time() < deadline:
        b = ser.read(1)
        if not b:
            continue
        buf.extend(b)
        if buf[-4:] == bytearray(HEADER):
            return True
    return False


def receive_data(ser: serial.Serial) -> bytes:
    """Read exactly TOTAL_BYTES with progress display."""
    data = bytearray()
    ser.timeout = DATA_TIMEOUT_S
    t0 = time.time()

    while len(data) < TOTAL_BYTES:
        remaining = TOTAL_BYTES - len(data)
        chunk = ser.read(min(4096, remaining))
        if not chunk:
            print("\nERROR: Timed out waiting for data.")
            return bytes()
        data.extend(chunk)

        pct       = 100.0 * len(data) / TOTAL_BYTES
        crps_done = len(data) * 8
        elapsed   = time.time() - t0
        rate      = crps_done / elapsed if elapsed > 0 else 0
        eta       = (TOTAL_CHALLENGES - crps_done) / rate if rate > 0 else 0
        print(f"\r  {pct:5.1f}%  {crps_done:>10,} / {TOTAL_CHALLENGES:,} CRPs"
              f"   {rate/1e3:5.1f} kCRP/s   ETA {eta:4.0f}s",
              end='', flush=True)

    print()
    return bytes(data)


def decode_and_save_csv(raw: bytes, csv_path: str) -> None:
    """Unpack raw byte stream into challenge,response CSV."""
    lines = []
    with open(csv_path, 'w', buffering=1 << 20) as f:
        f.write("challenge,response\n")
        for i, byte in enumerate(raw):
            for b in range(8):
                challenge = i * 8 + b
                response  = (byte >> b) & 1
                lines.append(f"{challenge},{response}\n")
            if len(lines) >= 100_000:
                f.writelines(lines)
                lines.clear()
        if lines:
            f.writelines(lines)


def main() -> None:
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    port     = sys.argv[1]
    num_runs = int(sys.argv[2]) if len(sys.argv) > 2 else 50

    os.makedirs(OUTPUT_DIR, exist_ok=True)

    print(f"Opening {port} at {BAUD_RATE} baud...")
    try:
        ser = serial.Serial(port, BAUD_RATE, timeout=1)
    except serial.SerialException as e:
        print(f"ERROR: {e}")
        sys.exit(1)

    print("=" * 65)
    print(f" Ready to collect {num_runs} CRP runs.")
    print(" Save directory:", OUTPUT_DIR)
    print("=" * 65)

    for run_idx in range(1, num_runs + 1):
        csv_filename = f"crp_run_{run_idx}.csv"
        csv_path = os.path.join(OUTPUT_DIR, csv_filename)

        ser.reset_input_buffer()
        print(f"\n[RUN {run_idx}/{num_runs}] Press BTNU on Basys3 to start sweep...")

        if not find_header(ser):
            print(f"ERROR: Sync header timed out on run {run_idx}. Exiting.")
            ser.close()
            sys.exit(1)

        t_start = time.time()
        raw = receive_data(ser)

        if len(raw) != TOTAL_BYTES:
            print(f"ERROR: Incomplete data ({len(raw)} / {TOTAL_BYTES} bytes).")
            ser.close()
            sys.exit(1)

        elapsed = time.time() - t_start
        print(f"  Received in {elapsed:.2f}s. Decoding & saving to {csv_filename}...")
        decode_and_save_csv(raw, csv_path)
        print(f"  Saved → {csv_path}")

    ser.close()
    print("\n" + "=" * 65)
    print(f" Successfully collected all {num_runs} runs in {OUTPUT_DIR}")
    print("=" * 65)


if __name__ == "__main__":
    main()