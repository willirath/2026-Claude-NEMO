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

Run with the default timestep count (from the container's namelist):

```bash
sbatch hpc/job.sh
```

Override the number of timesteps (e.g., 108000 for ~10 years at rn_Dt=2880):

```bash
NEMO_ITEND=108000 sbatch hpc/job.sh
```

## Output

Each job creates a run directory at `<repo>/runs/run_<PID>/` containing:

- `GYRE_*_grid_T.nc` — Temperature, salinity, SSH
- `GYRE_*_grid_U.nc` — U-velocity
- `GYRE_*_grid_V.nc` — V-velocity
- `GYRE_*_grid_W.nc` — W-velocity
- `mesh_mask.nc` — Grid geometry and masks

## Customization

**MPI ranks**: Edit `--tasks-per-node` in `job.sh`. The rebuild step
automatically uses `$SLURM_NTASKS`.

**Run length**: Set `NEMO_ITEND` as shown above, or edit the namelist in
`$RUNDIR/namelist_cfg` before submitting.

**SIF location**: Override with `SIF=/path/to/image.sif sbatch hpc/job.sh`.

**Run directory**: Override with `RUNDIR=/path/to/rundir sbatch hpc/job.sh`.
