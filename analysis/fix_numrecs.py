#!/usr/bin/env python3
"""Patch numrecs in NetCDF-3 processor files using the known step count.

IOIPSL keeps output files open for the entire run and only syncs numrecs to
disk on close.  The data is physically present (the file grows), but the
header still says 0 records.

Rather than inferring the record count from the file size (which requires
exact knowledge of the internal record layout), we compute it directly from
the NEMO time step counter:

    numrecs = step // nn_write

where `step` comes from the time.step file in the run directory and
`nn_write` is the output frequency in timesteps.

Usage:
    python fix_numrecs.py <directory> [nn_write]

    directory  directory containing *_NNNN.nc processor files AND time.step
    nn_write   output frequency in timesteps (default: 300 = 10 days at
               rn_Dt=2880 s; override with e.g. 3600 for rn_Dt=720 s)
"""
import struct
import sys
from pathlib import Path


def patch_numrecs(path, numrecs):
    path = Path(path)
    with open(path, 'r+b') as f:
        magic = f.read(4)
        if magic not in (b'CDF\x01', b'CDF\x02'):
            print(f"  SKIP  {path.name}: not a NetCDF-3 file")
            return
        current = struct.unpack('>I', f.read(4))[0]
        if current == numrecs:
            print(f"  OK    {path.name}: already {numrecs} records")
            return
        f.seek(4)
        f.write(struct.pack('>I', numrecs))
        print(f"  PATCH {path.name}: {current} → {numrecs}")


if __name__ == '__main__':
    directory = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('../output')
    nn_write = int(sys.argv[2]) if len(sys.argv) > 2 else 300

    timestep_file = directory / 'time.step'
    if not timestep_file.exists():
        print(f"No time.step in {directory} — cannot determine record count")
        sys.exit(1)

    step = int(timestep_file.read_text().strip())
    numrecs = step // nn_write
    print(f"time.step={step}, nn_write={nn_write} → numrecs={numrecs}")

    files = sorted(directory.glob('*_[0-9][0-9][0-9][0-9].nc'))
    if not files:
        print(f"No processor files (*_NNNN.nc) found in {directory}")
        sys.exit(1)

    for f in files:
        patch_numrecs(f, numrecs)
