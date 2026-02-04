# NEMO GYRE

Dockerized [NEMO](https://www.nemo-ocean.eu/) ocean model running the
GYRE configuration — an idealized double-gyre basin on a beta-plane.

## Prerequisites

- Docker
- [Pixi](https://pixi.sh/) (for Python analysis)

## Quick start

```bash
make all        # build → run → analyze
```

Individual targets:

```bash
make build      # build Docker image with compiled NEMO
make run        # run 2-year simulation, output to output/
make analyze    # generate plots from simulation output
make clean      # remove output directory
```

## Output

The simulation produces 10-day averaged NetCDF files:

- `grid_{T,U,V,W}_*.nc` — temperature, salinity, SSH, velocities
- `mesh_mask.nc` — grid geometry and land/sea mask
- `restart*.nc` — restart files for continuing the run

Analysis generates `output/ssh_variance.png`.

## Configuration

- **Resolution**: ~1° (32×22 grid, 31 vertical levels)
- **Run length**: 2 years (4320 timesteps, dt=4h)
- **Output**: IOIPSL (no XIOS dependency)
- **Physics only**: no biogeochemistry (PISCES/TOP disabled)

## Structure

```
Dockerfile              # builds NEMO in Debian bookworm
Makefile                # build/run/analyze pipeline
docker/arch-docker.fcm  # compiler/linker settings for Docker
analysis/               # Python analysis scripts
output/                 # simulation output (gitignored *.nc)
plans/                  # development milestone notes
nemo/                   # NEMO source (git submodule)
```

## Setup from scratch

```bash
git clone --recurse-submodules <repo-url>
pixi install
make all
```
