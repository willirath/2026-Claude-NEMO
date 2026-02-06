#!/bin/bash
#SBATCH --job-name=nemo-gyre
#SBATCH --partition=base
#SBATCH --nodes=1
#SBATCH --tasks-per-node=4
#SBATCH --cpus-per-task=1
#SBATCH --mem=8G
#SBATCH --time=06:00:00
#SBATCH --output=nemo-gyre_%j.out
#SBATCH --error=nemo-gyre_%j.err

module load gcc12-env/12.3.0
module load singularity/3.11.5

# Resolve repo root relative to this script
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Keep singularity cache off $HOME (quota'd)
export SINGULARITY_CACHEDIR=${SINGULARITY_CACHEDIR:-$REPO_DIR/.singularity_cache}

SIF=${SIF:-$REPO_DIR/nemo-gyre.sif}
RUNDIR=${RUNDIR:-$REPO_DIR/runs/run_$$}
mkdir -p "$RUNDIR"

# Copy namelists out of container for editing, then bind-mount back
singularity exec "$SIF" cp /opt/nemo-run/namelist_cfg "$RUNDIR/namelist_cfg"
singularity exec "$SIF" cp /opt/nemo-run/namelist_ref "$RUNDIR/namelist_ref"

# Override nn_itend if NEMO_ITEND is set (default: keep container value)
if [ -n "$NEMO_ITEND" ]; then
  sed -i "s/nn_itend *=.*/nn_itend = $NEMO_ITEND/" "$RUNDIR/namelist_cfg"
  sed -i "s/nn_stock *=.*/nn_stock = $NEMO_ITEND/" "$RUNDIR/namelist_cfg"
fi

# Run NEMO with container MPI (single-node, shared-memory only)
NP=$SLURM_NTASKS
singularity exec --bind "$RUNDIR:/opt/nemo-run" "$SIF" \
  mpirun -np "$NP" /opt/nemo-run/nemo

# Rebuild multi-rank output (serial, inside container)
singularity exec --bind "$RUNDIR:/opt/nemo-run" "$SIF" bash -c "
  cd /opt/nemo-run
  for f in *_grid_T_0000.nc *_grid_U_0000.nc *_grid_V_0000.nc *_grid_W_0000.nc; do
    [ -f \"\$f\" ] || continue
    base=\${f%_0000.nc}
    /opt/nemo-code/tools/REBUILD_NEMO/rebuild_nemo \${base} $NP && \
      rm -f \${base}_[0-9][0-9][0-9][0-9].nc
  done
  if [ -f mesh_mask_0000.nc ]; then
    /opt/nemo-code/tools/REBUILD_NEMO/rebuild_nemo mesh_mask $NP && \
      rm -f mesh_mask_[0-9][0-9][0-9][0-9].nc
  fi
"

echo "Output in $RUNDIR"
ls -lh "$RUNDIR"/*.nc
