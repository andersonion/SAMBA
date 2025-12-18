from __future__ import annotations

import io
import os
import struct
import subprocess
from dataclasses import dataclass
from typing import BinaryIO, Dict, List, Optional, Sequence, Tuple, Union

import numpy as np
import nibabel as nib


# ----------------------------
# Decompression stream openers
# ----------------------------

@dataclass
class DecompressedStream:
    stream: BinaryIO
    proc: Optional[subprocess.Popen] = None  # if using pigz/gunzip

    def close(self) -> None:
        try:
            self.stream.close()
        finally:
            if self.proc is not None:
                # ensure process exits; don't hang
                try:
                    self.proc.terminate()
                except Exception:
                    pass
                try:
                    self.proc.wait(timeout=1.0)
                except Exception:
                    pass


def _which(cmd: str) -> Optional[str]:
    for p in os.environ.get("PATH", "").split(os.pathsep):
        c = os.path.join(p, cmd)
        if os.path.isfile(c) and os.access(c, os.X_OK):
            return c
    return None


def open_decompressed_stream(path: str, *, prefer_pigz: bool = True) -> DecompressedStream:
    """
    Return a *decompressed* byte stream for a .gz file WITHOUT scratch files.
    - If prefer_pigz and pigz exists: uses `pigz -dc path` (multi-threaded)
    - else if gunzip exists: uses `gunzip -c path`
    - else: uses Python gzip module (single-threaded)

    Caller must close() it.
    """
    prefer_pigz = prefer_pigz and (os.environ.get("SAMBA_NO_PIGZ", "0") not in ("1", "true", "TRUE", "yes", "YES"))

    if not path.lower().endswith(".gz"):
        # Plain .nii: just open raw bytes.
        return DecompressedStream(stream=open(path, "rb"), proc=None)

    if prefer_pigz:
        pigz = _which("pigz")
        if pigz:
            proc = subprocess.Popen([pigz, "-dc", path], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            assert proc.stdout is not None
            return DecompressedStream(stream=proc.stdout, proc=proc)

    gunzip = _which("gunzip")
    if gunzip:
        proc = subprocess.Popen([gunzip, "-c", path], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        assert proc.stdout is not None
        return DecompressedStream(stream=proc.stdout, proc=proc)

    # Fallback: pure Python streaming (still no scratch)
    import gzip
    return DecompressedStream(stream=gzip.open(path, "rb"), proc=None)


def read_exact(stream: BinaryIO, nbytes: int) -> bytes:
    """Read exactly nbytes or raise."""
    out = bytearray(nbytes)
    mv = memoryview(out)
    got = 0
    while got < nbytes:
        n = stream.readinto(mv[got:]) if hasattr(stream, "readinto") else None
        if n is None:
            chunk = stream.read(nbytes - got)
            if not chunk:
                break
            mv[got:got + len(chunk)] = chunk
            got += len(chunk)
        else:
            if n == 0:
                break
            got += n
    if got != nbytes:
        raise IOError(f"Short read: got {got} of {nbytes} bytes")
    return bytes(out)


# ----------------------------
# gunzip_load-style var specs
# ----------------------------

VarSpec = Tuple[Union[int, float], str, str, str]  # (byte_count, dtype, name, endian)


def _dtype_from_string(dtype_str: str) -> np.dtype:
    # handle MATLAB-ish names
    m = {
        "uint8": np.uint8,
        "int8": np.int8,
        "uint16": np.uint16,
        "int16": np.int16,
        "uint32": np.uint32,
        "int32": np.int32,
        "uint64": np.uint64,
        "int64": np.int64,
        "single": np.float32,
        "float32": np.float32,
        "double": np.float64,
        "float64": np.float64,
    }
    if dtype_str not in m:
        raise ValueError(f"Unsupported dtype string: {dtype_str}")
    return np.dtype(m[dtype_str])


def gunzip_load_stream(
    path: str,
    var_specs: Optional[Sequence[VarSpec]] = None,
    max_read: Union[int, float] = float("inf"),
    *,
    prefer_pigz: bool = True,
) -> Dict[str, np.ndarray]:
    """
    Python analog of your gunzip_load with var_specifications.

    var_specs: sequence of (decompressed_byte_count, dtype_str, name, endian)
              endian is 'little' or 'big' (accepts prefixes)
    max_read: stop after this many decompressed bytes (streaming mode)
    """
    if var_specs is None:
        var_specs = [(float("inf"), "uint8", "data", "little")]

    # normalize endian
    norm_specs: List[VarSpec] = []
    for bc, dt, nm, en in var_specs:
        en_l = en.lower()
        if en_l.startswith("l"):
            en_n = "little"
        elif en_l.startswith("b"):
            en_n = "big"
        else:
            en_n = "little"
        norm_specs.append((bc, dt, nm, en_n))

    ds = open_decompressed_stream(path, prefer_pigz=prefer_pigz)
    try:
        out: Dict[str, List[np.ndarray]] = {nm: [] for _, _, nm, _ in norm_specs}

        total = 0
        for byte_count, dtype_str, name, endian in norm_specs:
            if total >= max_read:
                break

            if byte_count == float("inf"):
                # read remainder (bounded by max_read if set)
                if max_read == float("inf"):
                    raw = ds.stream.read()
                else:
                    raw = ds.stream.read(int(max_read - total))
                total += len(raw)

                arr_u8 = np.frombuffer(raw, dtype=np.uint8)
                if dtype_str == "uint8":
                    out[name].append(arr_u8.copy())
                else:
                    dt = _dtype_from_string(dtype_str)
                    # trim to multiple of element size
                    nbytes = (arr_u8.size // dt.itemsize) * dt.itemsize
                    arr_u8 = arr_u8[:nbytes]
                    arr = arr_u8.view(dt)
                    if endian == "big" and dt.itemsize > 1:
                        arr = arr.byteswap()
                    out[name].append(arr.copy())
            else:
                bc = int(byte_count)
                raw = read_exact(ds.stream, bc)
                total += bc

                u8 = np.frombuffer(raw, dtype=np.uint8)
                if dtype_str == "uint8":
                    out[name].append(u8.copy())
                else:
                    dt = _dtype_from_string(dtype_str)
                    if u8.size % dt.itemsize != 0:
                        # keep only full elements (like your unused_bytes logic)
                        nbytes = (u8.size // dt.itemsize) * dt.itemsize
                        u8 = u8[:nbytes]
                    arr = u8.view(dt)
                    if endian == "big" and dt.itemsize > 1:
                        arr = arr.byteswap()
                    out[name].append(arr.copy())

        # concatenate per field
        final: Dict[str, np.ndarray] = {}
        for nm, chunks in out.items():
            if len(chunks) == 0:
                final[nm] = np.zeros((0,), dtype=np.uint8)
            else:
                final[nm] = np.concatenate(chunks, axis=0)

        return final
    finally:
        ds.close()


# ----------------------------
# NIfTI streaming reader
# ----------------------------

def load_niigz_streaming(
    path: str,
    *,
    prefer_pigz: bool = True,
) -> Tuple[nib.Nifti1Header, np.ndarray, Optional[bytes]]:
    """
    Stream read NIfTI payload (no scratch).
    Returns (header, data_array_in_standard_shape, extra_bytes_between_352_and_vox_offset).
    """
    ds = open_decompressed_stream(path, prefer_pigz=prefer_pigz)
    try:
        hdr_bytes = read_exact(ds.stream, 348)

        le = struct.unpack("<i", hdr_bytes[0:4])[0]
        be = struct.unpack(">i", hdr_bytes[0:4])[0]
        if le == 348:
            endian = "<"
        elif be == 348:
            endian = ">"
        else:
            raise ValueError("Bad NIfTI header: sizeof_hdr != 348")

        hdr = nib.Nifti1Header.from_fileobj(io.BytesIO(hdr_bytes))
        vox_offset = float(hdr["vox_offset"])
        if vox_offset < 352:
            vox_offset = 352.0
        vox_offset_i = int(round(vox_offset))

        # read remaining header padding/extensions up to vox_offset
        pad = vox_offset_i - 348
        if pad < 0:
            raise ValueError("vox_offset < 348")
        pad_bytes = read_exact(ds.stream, pad)

        extra = None
        if vox_offset_i > 352:
            extra = pad_bytes[(352 - 348):]  # bytes between 352 and vox_offset

        dim = hdr["dim"].copy()
        dim[dim == 0] = 1
        n_dims7 = np.array(dim[1:8], dtype=int)
        n_elems = int(np.prod(n_dims7))

        base_dtype = hdr.get_data_dtype()
        file_dtype = np.dtype(base_dtype).newbyteorder(endian)

        out = np.empty(n_elems, dtype=file_dtype)
        buf = memoryview(out).cast("B")
        read_exact(ds.stream, buf.nbytes)  # but read_exact returns bytes; we want readinto

        # Replace above with true readinto into buf:
        # (we keep it explicit for speed + no intermediate bytes)
        # We'll do it properly:
    finally:
        ds.close()


def load_niigz_streaming_into_array(
    path: str,
    *,
    prefer_pigz: bool = True,
) -> Tuple[nib.Nifti1Header, np.ndarray, Optional[bytes]]:
    """
    Same as load_niigz_streaming but *actually* streams directly into the numpy array buffer.
    """
    ds = open_decompressed_stream(path, prefer_pigz=prefer_pigz)
    try:
        hdr_bytes = read_exact(ds.stream, 348)

        le = struct.unpack("<i", hdr_bytes[0:4])[0]
        be = struct.unpack(">i", hdr_bytes[0:4])[0]
        if le == 348:
            endian = "<"
        elif be == 348:
            endian = ">"
        else:
            raise ValueError("Bad NIfTI header: sizeof_hdr != 348")

        hdr = nib.Nifti1Header.from_fileobj(io.BytesIO(hdr_bytes))

        vox_offset = float(hdr["vox_offset"])
        if vox_offset < 352:
            vox_offset = 352.0
        vox_offset_i = int(round(vox_offset))

        pad = vox_offset_i - 348
        if pad < 0:
            raise ValueError("vox_offset < 348")
        pad_bytes = read_exact(ds.stream, pad)

        extra = None
        if vox_offset_i > 352:
            extra = pad_bytes[(352 - 348):]

        dim = hdr["dim"].copy()
        dim[dim == 0] = 1
        n_dims7 = np.array(dim[1:8], dtype=int)
        n_elems = int(np.prod(n_dims7))

        base_dtype = hdr.get_data_dtype()
        file_dtype = np.dtype(base_dtype).newbyteorder(endian)

        out_1d = np.empty(n_elems, dtype=file_dtype)
        buf = memoryview(out_1d).cast("B")
        want = buf.nbytes
        got = 0
        while got < want:
            n = ds.stream.readinto(buf[got:]) if hasattr(ds.stream, "readinto") else None
            if n is None:
                chunk = ds.stream.read(want - got)
                if not chunk:
                    break
                buf[got:got + len(chunk)] = chunk
                got += len(chunk)
            else:
                if n == 0:
                    break
                got += n
        if got != want:
            raise IOError(f"Short voxel read: got {got} / want {want} bytes")

        arr = out_1d.reshape(tuple(n_dims7))


        # convert to native endian for compute (NumPy 2.0 compatible)
        if arr.dtype.byteorder in (">", "<") and arr.dtype.byteorder != "=":
            arr = arr.byteswap().view(arr.dtype.newbyteorder("="))


        return hdr, arr, extra
    finally:
        ds.close()
