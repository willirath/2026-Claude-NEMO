#!/bin/bash
# Smoke test: 3 cycles of 300 steps each using Docker (macOS-friendly).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE=nemo-gyre
NP=4
NEMO_CYCLE=900    # 1 model month per cycle (30 days at rn_Dt=2880)
NEMO_ITEND=2700   # 3 cycles total

RUNDIR=$(mktemp -d "$REPO_DIR/runs/smoke-XXXXXX")
echo "Run dir: $RUNDIR"

# Point output/ at this run so 'make analyze' works at any time
# (only replace if output/ is already a symlink; don't clobber a real directory)
if [ -L "$REPO_DIR/output" ] || [ ! -e "$REPO_DIR/output" ]; then
    rm -f "$REPO_DIR/output"
    ln -s "$RUNDIR" "$REPO_DIR/output"
fi

# Copy namelists from container before bind-mounting RUNDIR over /opt/nemo-run
docker run --rm -v "$RUNDIR:$RUNDIR" "$IMAGE" \
    cp /opt/nemo-run/namelist_cfg "$RUNDIR/namelist_cfg.orig"
docker run --rm -v "$RUNDIR:$RUNDIR" "$IMAGE" \
    cp /opt/nemo-run/namelist_ref "$RUNDIR/namelist_ref"

# Reduce output frequency for smoke test: 1-day records (30 steps × 2880 s = 86400 s)
# This ensures each 1-month cycle contains 30 records with distinct calendar dates.
sed -i '' "s/nn_write *=.*/nn_write = 30/" "$RUNDIR/namelist_cfg.orig"

nn_it000=1
while [ "$nn_it000" -le "$NEMO_ITEND" ]; do
    nn_itend=$((nn_it000 + NEMO_CYCLE - 1))
    [ "$nn_itend" -gt "$NEMO_ITEND" ] && nn_itend=$NEMO_ITEND
    echo ""
    echo "=== Cycle: steps $nn_it000 → $nn_itend ==="

    cp "$RUNDIR/namelist_cfg.orig" "$RUNDIR/namelist_cfg"
    sed -i '' "s/nn_it000 *=.*/nn_it000 = $nn_it000/" "$RUNDIR/namelist_cfg"
    sed -i '' "s/nn_itend *=.*/nn_itend = $nn_itend/" "$RUNDIR/namelist_cfg"

    if [ "$nn_it000" -gt 1 ]; then
        prev_step=$(printf '%08d' $((nn_it000 - 1)))
        sed -i '' "s/ln_rstart *=.*/ln_rstart = .true./" "$RUNDIR/namelist_cfg"
        sed -i '' "s/cn_ocerst_indir *=.*/cn_ocerst_indir = \".\"/" "$RUNDIR/namelist_cfg"
        sed -i '' "s/cn_ocerst_in *=.*/cn_ocerst_in = \"GYRE_${prev_step}_restart\"/" "$RUNDIR/namelist_cfg"
    fi

    # Run NEMO
    docker run --rm --hostname nemo --cpus 4 --cpuset-cpus 0-3 \
        -v "$RUNDIR:/opt/nemo-run" -w /opt/nemo-run \
        "$IMAGE" \
        mpirun --allow-run-as-root -np $NP /opt/nemo-configs/GYRE_DOCKER/EXP00/nemo

    # Rebuild per-rank output for this cycle
    docker run --rm -v "$RUNDIR:/opt/nemo-run" "$IMAGE" bash -c "
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

    # Fix IOIPSL calendar attribute
    pixi run python -c "
from netCDF4 import Dataset
from glob import glob
for f in glob('$RUNDIR/*_grid_*.nc'):
    with Dataset(f, 'r+') as d:
        d['time_counter'].setncattr('calendar', '360_day')
"

    nn_it000=$((nn_itend + 1))
done

echo ""
echo "=== Smoke test complete ==="
ls -lh "$RUNDIR"/*.nc
