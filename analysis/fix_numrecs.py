#!/usr/bin/env python3
"""Patch numrecs in NetCDF-3 processor files where IOIPSL didn't flush the header.

IOIPSL keeps output files open for the entire run and only syncs numrecs to disk
on close.  The data is physically present (the file grows), but the header says
0 records, so readers see an empty file.

This script reads the header to find the record size and data start offset, then
computes the actual number of complete records from the file size and patches the
numrecs field (bytes 4–7 of the file).

After patching, rebuild_nemo can combine the processor files normally.

Usage:
    python fix_numrecs.py [directory]   # default: ../output
    python fix_numrecs.py /path/to/runs/run_12345
"""
import struct
import sys
from pathlib import Path


# ---------------------------------------------------------------------------
# NetCDF-3 type sizes
# ---------------------------------------------------------------------------
_NC_TYPE_SIZE = {1: 1, 2: 1, 3: 2, 4: 4, 5: 4, 6: 8}  # NC_BYTE..NC_DOUBLE


def _type_size(nc_type):
    return _NC_TYPE_SIZE.get(nc_type, 4)


# ---------------------------------------------------------------------------
# Minimal NetCDF-3 header parser
# ---------------------------------------------------------------------------
def parse_nc3_header(raw):
    """Return (numrecs_in_header, recsize, data_begin) from raw header bytes."""
    pos = 0
    magic = raw[pos:pos + 4]
    pos += 4
    if magic not in (b'CDF\x01', b'CDF\x02'):
        raise ValueError("Not a NetCDF-3 file")
    is_64 = magic == b'CDF\x02'

    def read_int():
        nonlocal pos
        v = struct.unpack('>I', raw[pos:pos + 4])[0]
        pos += 4
        return v

    def read_offset():
        nonlocal pos
        if is_64:
            v = struct.unpack('>Q', raw[pos:pos + 8])[0]
            pos += 8
        else:
            v = struct.unpack('>I', raw[pos:pos + 4])[0]
            pos += 4
        return v

    def read_string():
        nonlocal pos
        n = read_int()
        pos += (n + 3) & ~3
        return n  # caller doesn't need the name

    def skip_atts():
        tag = read_int()
        assert tag in (0, 12), f"Expected att tag, got {tag} at pos {pos}"
        count = read_int()
        for _ in range(count):
            read_string()
            att_type = read_int()
            att_len = read_int()
            nonlocal pos
            pos += (att_len * _type_size(att_type) + 3) & ~3

    numrecs = read_int()

    # Dimensions
    tag = read_int()
    assert tag in (0, 10), f"Expected dim tag, got {tag}"
    ndims = read_int()
    dim_ids = {}
    for i in range(ndims):
        read_string()
        size = read_int()
        dim_ids[i] = size  # 0 means UNLIMITED
    unlim_id = next((i for i, sz in dim_ids.items() if sz == 0), None)

    # Global attributes
    skip_atts()

    # Variables
    tag = read_int()
    assert tag in (0, 11), f"Expected var tag, got {tag}"
    nvars = read_int()

    recsize = 0
    data_begin = None

    for _ in range(nvars):
        read_string()
        ndimids = read_int()
        dimids = [read_int() for _ in range(ndimids)]
        skip_atts()
        read_int()        # type
        vsize = read_int()
        begin = read_offset()

        if unlim_id is not None and unlim_id in dimids:
            recsize += vsize  # vsize is already rounded to 4 bytes
            if data_begin is None or begin < data_begin:
                data_begin = begin

    return numrecs, recsize, data_begin


# ---------------------------------------------------------------------------
# Fix one file
# ---------------------------------------------------------------------------
def fix_numrecs(path):
    path = Path(path)
    file_size = path.stat().st_size

    # Header is small; 256 KB is more than enough for any NEMO output file
    with open(path, 'rb') as f:
        raw = f.read(min(file_size, 262144))

    try:
        numrecs_hdr, recsize, data_begin = parse_nc3_header(raw)
    except Exception as exc:
        print(f"  SKIP  {path.name}: {exc}")
        return

    if recsize == 0 or data_begin is None:
        print(f"  SKIP  {path.name}: no record variables")
        return

    actual = (file_size - data_begin) // recsize

    if numrecs_hdr == actual:
        print(f"  OK    {path.name}: {actual} records (header correct)")
        return

    print(f"  PATCH {path.name}: {numrecs_hdr} → {actual} records")
    with open(path, 'r+b') as f:
        f.seek(4)
        f.write(struct.pack('>I', actual))


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
if __name__ == '__main__':
    output_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('../output')

    # Match per-processor files: names ending in _NNNN.nc (4-digit rank suffix)
    files = sorted(output_dir.glob('*_[0-9][0-9][0-9][0-9].nc'))
    if not files:
        print(f"No processor files (*_NNNN.nc) found in {output_dir}")
        sys.exit(1)

    for f in files:
        fix_numrecs(f)
