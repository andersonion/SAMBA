import os
import numpy as np
import nibabel as nib

from samba_py.niigz_io import load_niigz_streaming_into_array


def test_streaming_reader_roundtrip(tmp_path):
    # Create a tiny nifti, gzip it, then read with streaming loader
    data = (np.arange(2*3*4, dtype=np.int16).reshape((2,3,4)))
    img = nib.Nifti1Image(data, affine=np.eye(4))

    out_nii = tmp_path / "tiny.nii.gz"
    nib.save(img, str(out_nii))

    hdr, arr, extra = load_niigz_streaming_into_array(str(out_nii), prefer_pigz=False)

    assert arr.shape[:3] == data.shape
    # nibabel may save as 3D with extra singleton dims; our reader returns 7D (X,Y,Z,T,U,V,W)
    assert arr.shape[0:3] == (2,3,4)
