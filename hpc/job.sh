#!/bin/bash
#SBATCH --job-name=nemo-gyre
#SBATCH --partition=base
#SBATCH --nodes=1
#SBATCH --tasks-per-node=4
#SBATCH --cpus-per-task=1
#SBATCH --mem=8G
#SBATCH --time=24:00:00
#SBATCH --output=nemo-gyre_%j.out
#SBATCH --error=nemo-gyre_%j.err

module load gcc12-env/12.3.0
module load singularity/3.11.5
module load nco

# Compute nodes need an explicit proxy for internet access
export http_proxy=http://10.0.7.235:3128
export https_proxy=http://10.0.7.235:3128

# SLURM copies the script to a spool dir, so use the submit directory
REPO_DIR="${SLURM_SUBMIT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"

# Keep singularity cache off $HOME (quota'd)
export SINGULARITY_CACHEDIR=${SINGULARITY_CACHEDIR:-$REPO_DIR/.singularity_cache}

SIF=${SIF:-$REPO_DIR/nemo-gyre.sif}
RUNDIR=${RUNDIR:-$REPO_DIR/runs/run_${SLURM_JOB_ID:?SLURM_JOB_ID not set – submit via sbatch}}
mkdir -p "$RUNDIR"

# Copy namelists out of container once; namelist_cfg.orig is the clean template
singularity exec --bind "$RUNDIR:$RUNDIR" "$SIF" cp /opt/nemo-run/namelist_cfg "$RUNDIR/namelist_cfg.orig"
singularity exec --bind "$RUNDIR:$RUNDIR" "$SIF" cp /opt/nemo-run/namelist_ref "$RUNDIR/namelist_ref"

# Symlink output/ now so 'make analyze' works for a preliminary look at any time
rm -f "$REPO_DIR/output"
ln -s "$RUNDIR" "$REPO_DIR/output"

# ---------------------------------------------------------------------------
# Cycled run: NEMO_CYCLE steps per cycle (default 10800 = 1 year at rn_Dt=2880)
# Total run length: NEMO_ITEND steps (default 637200 = 59 years)
# ---------------------------------------------------------------------------
NEMO_CYCLE=${NEMO_CYCLE:-10800}
NEMO_ITEND=${NEMO_ITEND:-637200}
NP=$SLURM_NTASKS
export OMPI_MCA_orte_tmpdir_base=/tmp

nn_it000=1
while [ "$nn_it000" -le "$NEMO_ITEND" ]; do
    nn_itend=$((nn_it000 + NEMO_CYCLE - 1))
    [ "$nn_itend" -gt "$NEMO_ITEND" ] && nn_itend=$NEMO_ITEND

    echo "=== Cycle: steps $nn_it000 → $nn_itend ==="

    # Restore clean namelist for this cycle
    cp "$RUNDIR/namelist_cfg.orig" "$RUNDIR/namelist_cfg"
    sed -i "s/nn_it000 *=.*/nn_it000 = $nn_it000/" "$RUNDIR/namelist_cfg"
    sed -i "s/nn_itend *=.*/nn_itend = $nn_itend/" "$RUNDIR/namelist_cfg"

    # All cycles after the first restart from the previous cycle's last step
    if [ "$nn_it000" -gt 1 ]; then
        prev_step=$(printf '%08d' $((nn_it000 - 1)))
        sed -i "s/ln_rstart *=.*/ln_rstart = .true./" "$RUNDIR/namelist_cfg"
        sed -i "s/cn_ocerst_indir *=.*/cn_ocerst_indir = \".\"/" "$RUNDIR/namelist_cfg"
        sed -i "s/cn_ocerst_in *=.*/cn_ocerst_in = \"GYRE_${prev_step}_restart\"/" "$RUNDIR/namelist_cfg"
    fi

    # Run NEMO
    singularity exec --bind "$RUNDIR:/opt/nemo-run" --pwd /opt/nemo-run "$SIF" \
        mpirun -np "$NP" /opt/nemo-configs/GYRE_DOCKER/EXP00/nemo

    # Rebuild multi-rank output for this cycle
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

    # Fix IOIPSL '360d' → CF-compliant '360_day' on any newly rebuilt files
    for f in "$RUNDIR"/*_grid_*.nc; do
        [ -f "$f" ] || continue
        ncatted -h -a calendar,time_counter,m,c,"360_day" "$f"
    done

    nn_it000=$((nn_itend + 1))
done

echo "All cycles complete. Output in $RUNDIR"
ls -lh "$RUNDIR"/*.nc

# Run analysis notebooks
make -C "$REPO_DIR" analyze
