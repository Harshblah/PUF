#!/usr/bin/env python3
"""
pc_crp_logger.py

Sends 32-bit challenges to the Basys 3 over UART and logs the 64-bit
PUF responses to a CSV, so you can build up a CRP database and later
compute Intra-HD (reliability), uniformity, and (with a second board)
uniqueness -- see the "On evaluation" section of your lessons-learned
notes: always check Intra-HD first before trusting any other metric.

Usage:
    pip install pyserial
    python pc_crp_logger.py --port COM5 --n 50 --repeats 10 --out crps.csv

Each challenge is sent CHAL_REPEATS times in a row so you can measure
Intra-HD (bit-flip rate for a fixed challenge) directly from the log.
"""
import argparse
import csv
import random
import struct
import sys
import time

import serial

BAUD = 115200
CHAL_BYTES = 4
RESP_BYTES = 8


def send_challenge(ser: serial.Serial, challenge: int) -> int:
    ser.write(struct.pack(">I", challenge))
    resp = ser.read(RESP_BYTES)
    if len(resp) != RESP_BYTES:
        raise TimeoutError(
            f"Expected {RESP_BYTES} bytes, got {len(resp)}. "
            "Check baud rate / cable / that the FSM is in S_RX_CHAL."
        )
    return int.from_bytes(resp, "big")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", required=True, help="e.g. COM5 or /dev/ttyUSB1")
    ap.add_argument("--n", type=int, default=20, help="number of distinct challenges")
    ap.add_argument("--repeats", type=int, default=10,
                     help="repeats per challenge, for Intra-HD measurement")
    ap.add_argument("--out", default="crps.csv")
    ap.add_argument("--timeout", type=float, default=1.0)
    args = ap.parse_args()

    ser = serial.Serial(args.port, BAUD, timeout=args.timeout)
    time.sleep(2.0)  # let the FPGA UART settle / board reset from DTR toggle

    challenges = [random.getrandbits(32) for _ in range(args.n)]

    with open(args.out, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["challenge_hex", "trial", "response_hex", "response_bin64"])

        for c in challenges:
            for trial in range(args.repeats):
                r = send_challenge(ser, c)
                writer.writerow([
                    f"{c:08X}", trial, f"{r:016X}", f"{r:064b}"
                ])
                print(f"challenge={c:08X} trial={trial} response={r:016X}")

    ser.close()
    print(f"\nWrote {args.n * args.repeats} rows to {args.out}")
    print("Next: compute Intra-HD from repeated rows for the SAME challenge "
          "before trusting uniformity/uniqueness numbers.")


if __name__ == "__main__":
    sys.exit(main())
