# Milestone 1: Dockerfile — Build NEMO GYRE_PISCES (no XIOS)

## Goal

A Docker image that contains a compiled `nemo` executable for the
GYRE_PISCES configuration, ready to run.

## Approach

### Base image
`debian:bookworm` — stable, well-tested with gfortran + OpenMPI.

### System packages
- `gfortran`, `cpp`, `make` — Fortran build toolchain
- `libopenmpi-dev`, `openmpi-bin` — MPI (NEMO uses `mpif90`)
- `libnetcdf-dev`, `libnetcdff-dev` — NetCDF C + Fortran
- `libhdf5-dev` — HDF5 (NetCDF4 backend)
- `perl` — required by FCM build system

### Architecture file
Create `arch-docker.fcm` based on `arch-linux_gfortran.fcm`:
- Point `NCDF_*` to Debian package paths (`/usr`)
- Remove XIOS entries from `USER_INC` / `USER_LIB`
- Keep `mpif90` as compiler/linker

### CPP keys
Modify from: `key_top key_linssh key_vco_1d key_xios`
To: `key_top key_linssh key_vco_1d`

### Build command
```
./makenemo -m docker -r GYRE_PISCES -n MY_GYRE
```
This creates `cfgs/MY_GYRE/EXP00/nemo` and copies EXPREF files.

### Output mechanism
Without `key_xios`, `diawri.F90` uses the IOIPSL path (bundled in
`ext/IOIPSL`). It writes `grid_{T,U,V,W}*.nc` files every `nn_write`
timesteps (currently 60, i.e. every 60 × 14400s = 10 days).

## Files to create
- `Dockerfile`
- `docker/arch-docker.fcm`
- `Makefile` — workflow driver with targets:
  - `build` — `docker build -t nemo-gyre .`
  - `run` — `docker run` with volume mount for output
  - `clean` — remove output, containers
  - More targets added as we go (analysis, etc.)

## Verification
```bash
make build
docker run --rm nemo-gyre ls -la /nemo/cfgs/MY_GYRE/EXP00/nemo
```
The executable should exist and be non-zero size.
