# Running NEMO GYRE on NESH

## Prerequisites

The Docker image must be pushed to GHCR first (from a local machine):

```bash
gh auth refresh -s write:packages
echo $(gh auth token) | docker login ghcr.io -u willirath --password-stdin
make push
```

## Setup on NESH

Clone the repo (or rsync it) to `$WORK`, then pull the SIF and set up the
Python analysis environment:

```bash
cd /path/to/repo
export SINGULARITY_CACHEDIR=$PWD/.singularity_cache
singularity pull nemo-gyre.sif docker://ghcr.io/willirath/2026-claude-nemo:latest

# Install pixi (once) and create the analysis environment
curl -fsSL https://pixi.sh/install.sh | bash
pixi install
```

The `.sif` file and `.singularity_cache/` are gitignored. Keep them in the repo — `$HOME` is quota'd.

## Submitting jobs

**Full 59-year run** (default, 1-year cycles):

```bash
sbatch hpc/job.sh
```

**Short test run** (e.g. 3 years):

```bash
NEMO_ITEND=32400 sbatch hpc/job.sh
```

## Cycled execution

The job runs NEMO in restart cycles internally — no separate job submission
per segment. After each cycle NEMO output is rebuilt and calendar-fixed, so
a preliminary look is always possible:

```bash
# While the job is running, from a login node:
OUTPUT_DIR=runs/run_<JOBID> make analyze
```

**Cycle length**: default 10800 steps (= 1 year at rn_Dt=2880). Override:

```bash
NEMO_CYCLE=108000 sbatch hpc/job.sh   # 10-year cycles
```

## Output

Each job creates a run directory at `runs/run_<JOBID>/` and symlinks `output/`
to it. The directory accumulates output across all cycles:

- `GYRE_*_grid_{T,U,V,W}.nc` — per-cycle ocean fields (rebuilt, calendar-fixed)
- `mesh_mask.nc` — grid geometry and masks (written on first cycle)
- `GYRE_*_restart_000X.nc` — per-rank restart files from each cycle
- `namelist_cfg`, `namelist_ref` — namelists used (patched per cycle)

## Customization

**MPI ranks**: Edit `--tasks-per-node` in `job.sh`. The rebuild step uses
`$SLURM_NTASKS` automatically.

**SIF location**: `SIF=/path/to/image.sif sbatch hpc/job.sh`

**Run directory**: `RUNDIR=/path/to/rundir sbatch hpc/job.sh`
