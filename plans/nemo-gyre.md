# Plan: Run NEMO Gyre Configuration

## Overview

Build and run the NEMO ocean model GYRE_PISCES configuration inside Docker,
then analyze the output with Python (xarray/matplotlib/cartopy).

GYRE_PISCES is an idealized double-gyre basin on a beta-plane (closed
rectangular box, ~30N, 1deg resolution, 31 vertical levels) with PISCES
biogeochemistry. Analytical forcing — no input data files needed.

---

## Milestones

### 1. Dockerfile — build NEMO (no XIOS)

Single Dockerfile that:
- Installs system deps: gfortran, cpp, make, MPI (OpenMPI), NetCDF-C,
  NetCDF-Fortran, HDF5, Perl
- Builds NEMO GYRE_PISCES via `makenemo` **without `key_xios`**
- IOIPSL (bundled in `nemo/ext/IOIPSL`) provides native NetCDF output
- Produces a runnable image with the `nemo` executable

The cpp keys become: `key_top key_linssh key_vco_1d` (drop `key_xios`).

Output uses the IOIPSL path in `diawri.F90` (line 554+), which writes
traditional `grid_T`, `grid_U`, `grid_V`, `grid_W` NetCDF files every
`nn_write` timesteps via `histbeg`/`histdef`/`histwrite`.

Base image: `debian:bookworm` or `ubuntu:24.04`.

### 2. Run the simulation

- `docker run` with a volume mount for output
- Tweak `namelist_cfg` for a short test run (run length, output frequency
  via `nn_write`)
- `mpirun -np 1 ./nemo` (single process for first test)
- Verify it produces `grid_{T,U,V,W}*.nc` output files

### 3. Analyze output with Python

- Use xarray to open output NetCDF files
- Plot fields (SST, SSH, velocity, PISCES tracers) with
  matplotlib + cartopy
- Jupyter notebook for interactive exploration

### 4. (Deferred) Add XIOS support

If native IOIPSL output is insufficient (e.g., need online averaging,
custom output streams, or higher-res configs), add XIOS:
- Build XIOS2/3 in the Docker image
- Restore `key_xios` in cpp keys
- Configure via `iodef.xml` / `file_def_nemo.xml`

---

## Key files in the NEMO submodule

| Path | Purpose |
|------|---------|
| `nemo/makenemo` | Build script |
| `nemo/ext/IOIPSL/` | Bundled IOIPSL library (native NetCDF I/O) |
| `nemo/arch/arch-linux_gfortran.fcm` | Template arch file for gfortran |
| `nemo/cfgs/GYRE_PISCES/` | Config definition |
| `nemo/cfgs/GYRE_PISCES/cpp_GYRE_PISCES.fcm` | CPP keys (currently `key_top key_linssh key_vco_1d key_xios`) |
| `nemo/cfgs/GYRE_PISCES/EXPREF/namelist_cfg` | Main runtime config (`nn_write=60`) |
| `nemo/src/OCE/DIA/diawri.F90` | Diagnostics output — IOIPSL path at line 554 |
