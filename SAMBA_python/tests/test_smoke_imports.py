def test_imports():
    import numpy
    import nibabel
    import samba_py
    from samba_py import niigz_io
    assert numpy is not None
    assert nibabel is not None
    assert samba_py is not None
    assert niigz_io is not None
