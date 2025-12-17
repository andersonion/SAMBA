#!/usr/bin/env python3
"""
create_centered_mass_from_image_array.py

Python port of MATLAB create_centered_mass_from_image_array(in_file,out_file)

Behavior:
- Determine 3D dims from NIfTI header (dim 1..3).
- Create an all-zero 3D volume, then set a centered cube to 1.
  The cube spans approximately dims/4 in each axis (MATLAB frac=4 logic).
- Write output as a single 3D NIfTI (not 4D).
"""

import argparse
import numpy as np
import nibabel as nib


def create_centered_mass_from_image_array(in_file: str, out_file: str, frac: int = 4) -> None:
    # Load image + header lazily. nibabel will not necessarily read all voxel data here.
    img = nib.load(in_file)
    hdr = img.header.copy()

    # MATLAB: dims = nii.hdr.dime.dim(2:4)
    # nibabel: img.shape might be 3D or 4D+; we only care about first 3 axes.
    if len(img.shape) < 3:
        raise ValueError(f"Expected at least 3D NIfTI, got shape {img.shape}")

    dims = np.array(img.shape[:3], dtype=int)

    # MATLAB:
    # starters = ceil(dims*(1/2-1/(frac*2)));
    # enders   = starters + round(dims/frac);
    #
    # MATLAB indexing is 1-based and inclusive on both ends.
    # Python indexing is 0-based and end-exclusive.
    #
    # We'll compute MATLAB starters/enders in MATLAB's 1-based space,
    # then convert to Python slices.

    starters_matlab = np.ceil(dims * (0.5 - 1.0 / (frac * 2.0))).astype(int)  # 1-based
    sizes_matlab = np.round(dims / float(frac)).astype(int)
    enders_matlab = starters_matlab + sizes_matlab  # inclusive end in MATLAB

    # Convert to Python 0-based, end-exclusive:
    starts_py = starters_matlab - 1
    ends_py = enders_matlab  # because MATLAB inclusive end => python exclusive end is +0 here

    # Create output volume. MATLAB sometimes preserves datatype via nifti1('data_type', datatype).
    # We'll preserve the input on-disk dtype where possible; output is 0/1.
    out_dtype = hdr.get_data_dtype()
    data = np.zeros(tuple(dims), dtype=out_dtype)

    xs, ys, zs = (slice(starts_py[0], ends_py[0]),
                  slice(starts_py[1], ends_py[1]),
                  slice(starts_py[2], ends_py[2]))
    data[xs, ys, zs] = np.array(1, dtype=out_dtype)

    # Write a 3D NIfTI. Keep affine the same.
    out_img = nib.Nifti1Image(data, img.affine, header=hdr)

    # Force header to be 3D + single volume-ish, analogous to:
    # nii.hdr.dime.dim(1)=3; dim(5)=1; pixdim(1)=1; pixdim(5)=0;
    # In nibabel, dim[0] = number of dims; dim[4] corresponds to 4th axis (t)
    out_hdr = out_img.header
    out_hdr["dim"][0] = 3
    out_hdr["dim"][4] = 1
    out_hdr["pixdim"][0] = 1
    out_hdr["pixdim"][4] = 0

    nib.save(out_img, out_file)


def _cli():
    p = argparse.ArgumentParser(description="Create centered binary cube mask NIfTI (MATLAB port).")
    p.add_argument("in_file", help="Input NIfTI (.nii or .nii.gz)")
    p.add_argument("out_file", help="Output NIfTI (.nii or .nii.gz)")
    p.add_argument("--frac", type=int, default=4, help="Cube size factor (default: 4 means dims/4).")
    args = p.parse_args()
    create_centered_mass_from_image_array(args.in_file, args.out_file, frac=args.frac)


if __name__ == "__main__":
    _cli()
