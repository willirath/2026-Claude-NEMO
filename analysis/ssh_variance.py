"""Plot SSH variance from NEMO GYRE output."""

import sys
from pathlib import Path

import matplotlib.pyplot as plt
import xarray as xr

OUTPUT_DIR = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("output")

ds = xr.open_dataset(
    OUTPUT_DIR / "GYRE_10d_00010101_00021230_grid_T_0000.nc", decode_times=False
)

ssh = ds["sossheig"]
ssh_var = ssh.var("time_counter")

fig, ax = plt.subplots(figsize=(8, 6))
pcm = ax.pcolormesh(
    ds.nav_lon.values, ds.nav_lat.values, ssh_var.values, shading="auto", cmap="inferno"
)
fig.colorbar(pcm, ax=ax, label="SSH variance (m²)")
ax.set_xlabel("Longitude")
ax.set_ylabel("Latitude")
ax.set_title("NEMO GYRE — Sea Surface Height Variance (2-year run)")
ax.set_aspect("equal")
fig.tight_layout()

out = OUTPUT_DIR / "ssh_variance.png"
fig.savefig(out, dpi=150)
print(f"Saved {out}")
