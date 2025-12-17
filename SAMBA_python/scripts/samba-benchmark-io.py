#!/usr/bin/env python3
import argparse
import time
import numpy as np
import nibabel as nib

from samba_py.niigz_io import load_niigz_streaming_into_array


def bench(fn, reps=3):
    times = []
    for _ in range(reps):
        t0 = time.perf_counter()
        out = fn()
        t1 = time.perf_counter()
        times.append(t1 - t0)
    return times, out


def main():
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
    prefer = not args.no_pigz

    def nibabel_full_load():
        img = nib.load(path)
        data = np.asanyarray(img.dataobj)  # force full decompression/load
        return data.shape, data.dtype

    def streaming():
        hdr, arr, extra = load_niigz_streaming_into_array(
            path,
            prefer_pigz=prefer,
        )
        return (
            arr.shape,
            arr.dtype,
            0 if extra is None else len(extra),
        )

    label = "streaming(pigz)" if prefer else "streaming(gzip)"

    for name, fn in [
        ("nibabel(full load)", nibabel_full_load),
        (label, streaming),
    ]:
        times, out = bench(fn, reps=args.reps)
        best = min(times)
        avg = sum(times) / len(times)
        print(f"{name:28s} best={best:.3f}s avg={avg:.3f}s out={out}")


if __name__ == "__main__":
    main()
