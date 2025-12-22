#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import shutil
import time
from typing import Any, Callable, Tuple

import numpy as np
import nibabel as nib

from samba_py.niigz_io import load_niigz_streaming_into_array


def _mib_per_s(nbytes: int, seconds: float) -> float:
    if seconds <= 0:
        return float("inf")
    return (nbytes / (2**20)) / seconds


def _fmt_env_threads() -> str:
    keys = [
        "OMP_NUM_THREADS",
        "MKL_NUM_THREADS",
        "OPENBLAS_NUM_THREADS",
        "NUMEXPR_NUM_THREADS",
        "VECLIB_MAXIMUM_THREADS",
        "BLIS_NUM_THREADS",
        "PIGZ",
        "PIGZ_THREADS",
        "SAMBA_NO_PIGZ",
    ]
    parts = []
    for k in keys:
        v = os.environ.get(k)
        if v is not None:
            parts.append(f"{k}={v}")
    return " ".join(parts) if parts else "(no thread-related env vars set)"


def _detect_stream_backend(path: str, prefer_pigz: bool) -> str:
    """
    Mirror the logic in samba_py.niigz_io.open_decompressed_stream (roughly)
    so benchmark output makes the chosen backend explicit.
    """
    p = path.lower()
    if not p.endswith(".gz"):
        return "plain-file"

    samba_no_pigz = os.environ.get("SAMBA_NO_PIGZ", "0") in ("1", "true", "TRUE", "yes", "YES")
    if prefer_pigz and not samba_no_pigz:
        if shutil.which("pigz") is not None:
            return "pigz"

    if shutil.which("gunzip") is not None:
        return "gunzip"

    return "python-gzip"


def bench(fn: Callable[[], Tuple[Any, int]], reps: int = 3) -> Tuple[list[float], Any, int]:
    """
    fn returns (payload, nbytes) where nbytes is the decompressed payload size.
    """
    times: list[float] = []
    last_payload: Any = None
    last_nbytes: int = 0

    for _ in range(reps):
        t0 = time.perf_counter()
        payload, nbytes = fn()
        t1 = time.perf_counter()

        times.append(t1 - t0)
        last_payload = payload
        last_nbytes = nbytes

    return times, last_payload, last_nbytes


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("nii_gz", help="Path to .nii.gz (or .nii)")
    ap.add_argument("--reps", type=int, default=3)
    ap.add_argument(
        "--no-pigz",
        action="store_true",
        help="Disable pigz even if available",
    )
    args = ap.parse_args()

    path = args.nii_gz
    prefer_pigz = not args.no_pigz

    # ---- header: CPU and environment info ----
    cpu_count = os.cpu_count()
    pigz_path = shutil.which("pigz")
    gunzip_path = shutil.which("gunzip")

    print("=== Benchmark context ===")
    print(f"Host CPU cores (os.cpu_count): {cpu_count}")
    print(f"pigz:   {pigz_path if pigz_path else '(not found)'}")
    print(f"gunzip: {gunzip_path if gunzip_path else '(not found)'}")
    print(f"Thread env: {_fmt_env_threads()}")
    print(f"prefer_pigz (CLI): {prefer_pigz}")
    print(f"stream backend (predicted): {_detect_stream_backend(path, prefer_pigz)}")
    print("=========================")

    # ---- methods ----
    def nibabel_full_load() -> Tuple[Tuple[Any, ...], int]:
        img = nib.load(path)
        data = np.asanyarray(img.dataobj)  # force full decompression/load
        # bytes moved into memory (approx payload size)
        nbytes = int(data.size * data.dtype.itemsize)
        return (data.shape, data.dtype), nbytes

    def streaming() -> Tuple[Tuple[Any, ...], int]:
        hdr, arr, extra = load_niigz_streaming_into_array(
            path,
            prefer_pigz=prefer_pigz,
        )
        nbytes = int(arr.size * arr.dtype.itemsize)
        extra_len = 0 if extra is None else len(extra)
        return (arr.shape, arr.dtype, extra_len, _detect_stream_backend(path, prefer_pigz)), nbytes

    label_stream = "streaming(pigz)" if _detect_stream_backend(path, prefer_pigz) == "pigz" else "streaming(gzip)"

    for name, fn in [
        ("nibabel(full load)", nibabel_full_load),
        (label_stream, streaming),
    ]:
        times, out, nbytes = bench(fn, reps=args.reps)
        best = min(times)
        avg = sum(times) / len(times)

        best_mibs = _mib_per_s(nbytes, best)
        avg_mibs = _mib_per_s(nbytes, avg)

        print(
            f"{name:20s} "
            f"best={best:.3f}s ({best_mibs:8.1f} MiB/s)  "
            f"avg={avg:.3f}s ({avg_mibs:8.1f} MiB/s)  "
            f"bytes={nbytes}  out={out}"
        )


if __name__ == "__main__":
    main()
