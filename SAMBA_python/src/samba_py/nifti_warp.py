#!/usr/bin/env python3
"""
SAMBA Python - NIfTI warp utilities

Implements create_identity_warp() as a faithful translation of the MATLAB
create_identity_warp.m used in SAMBA.

- Reads an input NIfTI(.gz)
- Creates a zero displacement field with vector length 2 (2D) or 3 (3D)
- Writes output with NIfTI intent 'vector' (intent_code=1007)
- Designed for headless HPC/Singularity environments.

Author: SAMBA_python translation
"""

from __future__ import annotations

import os
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Optional, Tuple

import numpy as np
import nibabel as nib


@dataclass(frozen=True)
class IdentityWarpResult:
    output_path: Path
    success_code: int
    ndim_inferred: int
    out_shape: Tuple[int, ...]


def _resolve_output_path(
    image_nii: Path,
    optional_path: Optional[str] = None,
    default_name: str = "identity_warp",
    default_ext: str = ".nii.gz",
) -> Path:
    """
    MATLAB behavior:
      - default output dir = dir of input image_nii
      - optional arg can be:
          * an output directory
          * a full output file name (dir must exist)

    Notes:
      - MATLAB uses fileparts(tester) and checks exist(t_dir,'dir')==7
      - If t_ext != '' it assumes filename was provided.
    """
    image_nii = Path(image_nii)
    out_dir = image_nii.parent
    out_name = default_name
    out_ext = default_ext

    if optional_path:
        p = Path(optional_path)

        # If optional path is a directory that exists => use it
        if p.exists() and p.is_dir():
            out_dir = p
        else:
            # Treat as "maybe a file path": require that its parent dir exists
            parent = p.parent if str(p.parent) not in ("", ".") else out_dir
            if parent.exists() and parent.is_dir():
                # If it has an extension, assume it’s a filename
                # (We mimic MATLAB: any extension implies filename present.)
                if "".join(p.suffixes):
                    out_dir = parent
                    out_name = p.name
                    # Keep full suffix chain, e.g. ".nii.gz"
                    # If p.name already includes suffixes, this is fine.
                    return out_dir / out_name
                else:
                    # No extension => ambiguous; MATLAB would only switch dir
                    # when t_dir exists; here, we can treat this as a directory-like
                    # string but only if it's an existing directory (handled above).
                    # Otherwise, ignore and keep defaults.
                    pass

    return out_dir / f"{out_name}{out_ext}"


def _infer_2d_vs_3d(img: nib.Nifti1Image) -> int:
    """
    MATLAB check was dims(1) == 2 (i.e., NIfTI dim[0] == 2).
    However, many "2D" NIfTIs in the wild are stored as 3D with nz=1.
    To match MATLAB as closely as possible, we primarily trust header dim[0],
    but fall back to nz==1 as a secondary heuristic.

    Returns: 2 or 3
    """
    hdr = img.header
    dim0 = int(hdr["dim"][0])
    if dim0 == 2:
        return 2

    # Secondary heuristic: if nz == 1 and dim0 <= 3, consider it 2D-ish.
    # But MATLAB said "only guaranteed 2 and 3 dimensional images".
    nx, ny, nz = (int(hdr["dim"][1]), int(hdr["dim"][2]), int(hdr["dim"][3]))
    if nz == 1 and dim0 <= 3:
        return 2

    return 3


def _wait_for_file(path: Path, timeout_s: float = 5.0, poll_s: float = 0.2) -> bool:
    """
    HPC/shared FS can lag. MATLAB used pause(2) then exist().
    We instead poll up to timeout.
    """
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        if path.exists():
            return True
        time.sleep(poll_s)
    return path.exists()


def create_identity_warp(
    image_nii: str | os.PathLike,
    optional_output: Optional[str] = None,
    dtype: np.dtype = np.float64,
    timeout_s: float = 5.0,
) -> IdentityWarpResult:
    """
    Create an identity warp (zero displacement field) for a given NIfTI image.

    Parameters
    ----------
    image_nii
        Input NIfTI path.
    optional_output
        Optional output directory OR full output filename (parent dir must exist).
        If directory: output is <dir>/identity_warp.nii.gz
        If file: output is exactly that.
    dtype
        Output dtype. MATLAB zeros() defaults to double; default here is float64
        for fidelity.
    timeout_s
        How long to wait for the file to appear on disk (HPC FS latency).

    Returns
    -------
    IdentityWarpResult
        output_path, success_code (1/0), inferred ndim, and out_shape.
    """
    image_nii = Path(image_nii)
    if not image_nii.exists():
        raise FileNotFoundError(f"Input image not found: {image_nii}")

    output_path = _resolve_output_path(image_nii, optional_output)

    # Load input NIfTI
    img = nib.load(str(image_nii))
    hdr = img.header.copy()
    affine = img.affine

    # Read dims from header (NIfTI dim array)
    # hdr['dim'] is length 8: [ndim, dim1, dim2, dim3, dim4, dim5, dim6, dim7]
    dims = hdr["dim"].astype(np.int16).copy()

    # Create zeros array of size dims(2:5) in MATLAB => dim1..dim4 in NIfTI
    dim1 = int(dims[1])
    dim2 = int(dims[2])
    dim3 = int(dims[3]) if int(dims[0]) >= 3 else 1
    dim4 = int(dims[4]) if int(dims[0]) >= 4 else 1

    # Infer 2D vs 3D like MATLAB intent
    nd = _infer_2d_vs_3d(img)
    vec_len = 2 if nd == 2 else 3

    # MATLAB:
    #   zero_array = zeros(dims(2:5));
    #   new_image = cat(5, zero_array, ... vec_len times)
    # This yields shape: (dim1, dim2, dim3, dim4, vec_len)
    zero_array = np.zeros((dim1, dim2, dim3, dim4), dtype=dtype)
    new_image = np.stack([zero_array] * vec_len, axis=4)

    # Update header dims to 5D, set dim[5] = vec_len like MATLAB dims(6)=vec_len
    # and dim[0]=5
    dims_out = dims.copy()
    dims_out[0] = 5
    dims_out[1] = dim1
    dims_out[2] = dim2
    dims_out[3] = dim3
    dims_out[4] = dim4
    dims_out[5] = vec_len
    # Clear higher dims
    dims_out[6] = 1
    dims_out[7] = 1
    hdr["dim"] = dims_out

    # Set intent to 'vector' => intent_code 1007
    # nibabel will set intent_code accordingly.
    try:
        hdr.set_intent("vector")
    except Exception:
        # Fallback: set numeric intent code explicitly
        hdr["intent_code"] = 1007

    # Make sure datatype matches
    hdr.set_data_dtype(np.dtype(dtype))

    # Ensure output directory exists (MATLAB required it; we do too)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    # Write NIfTI
    out_img = nib.Nifti1Image(new_image, affine, header=hdr)
    nib.save(out_img, str(output_path))

    # Check for output (with FS latency handling)
    ok = _wait_for_file(output_path, timeout_s=timeout_s)
    success_code = 1 if ok else 0

    return IdentityWarpResult(
        output_path=output_path,
        success_code=success_code,
        ndim_inferred=nd,
        out_shape=tuple(int(x) for x in new_image.shape),
    )
