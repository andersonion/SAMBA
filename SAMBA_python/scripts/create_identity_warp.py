#!/usr/bin/env python3
"""
CLI wrapper for SAMBA_python identity warp creation.

Faithfully mirrors MATLAB create_identity_warp.m behavior:
- default output: <input_dir>/identity_warp.nii.gz
- optional second positional arg:
    * existing directory -> output written there
    * full filename (parent directory must exist) -> output written exactly there
- returns success code via exit status (0 success, 1 failure) and prints a
  one-line summary.

HPC/Singularity-safe: no GUI, no interactive prompts.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np

# Import from src layout:
# If SAMBA_python is installed (editable or wheel), this will work.
# If running directly from repo without install, ensure PYTHONPATH includes SAMBA_python/src.
from samba_python.nifti_warp import create_identity_warp


def _parse_dtype(s: str) -> np.dtype:
    s = s.strip().lower()
    if s in ("float64", "double", "f8"):
        return np.float64
    if s in ("float32", "single", "f4"):
        return np.float32
    raise argparse.ArgumentTypeError(f"Unsupported dtype: {s} (use float64 or float32)")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        description="Create an identity displacement field (vector intent) for a given NIfTI image."
    )
    parser.add_argument(
        "image_nii",
        help="Input image NIfTI (.nii or .nii.gz).",
    )
    parser.add_argument(
        "output",
        nargs="?",
        default=None,
        help=(
            "Optional: output directory OR full output filename. "
            "If directory exists -> writes <dir>/identity_warp.nii.gz. "
            "If filename is given -> parent directory must exist."
        ),
    )
    parser.add_argument(
        "--dtype",
        type=_parse_dtype,
        default=np.float64,
        help="Output dtype (MATLAB zeros() is float64). Options: float64, float32. Default: float64.",
    )
    parser.add_argument(
        "--timeout-s",
        type=float,
        default=5.0,
        help="Seconds to wait for output file to appear (shared FS latency). Default: 5.0.",
    )

    args = parser.parse_args(argv)

    result = create_identity_warp(
        args.image_nii,
        optional_output=args.output,
        dtype=args.dtype,
        timeout_s=args.timeout_s,
    )

    # MATLAB returns 1 on success, 0 on failure; exit codes are opposite convention.
    # We'll print the MATLAB-style success_code but return POSIX: 0 success, 1 failure.
    print(
        f"[create_identity_warp] success_code={result.success_code} "
        f"ndim_inferred={result.ndim_inferred} out_shape={result.out_shape} "
        f"output={result.output_path}"
    )

    return 0 if result.success_code == 1 else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
