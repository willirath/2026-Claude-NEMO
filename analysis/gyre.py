"""Shared utilities for NEMO GYRE analysis notebooks.

Centralises grid loading, masking, coordinate fixes, vector rotation,
and cartopy map setup so each notebook's setup cell is just a few lines.
"""

from __future__ import annotations

from pathlib import Path

import cartopy.crs as ccrs
import cartopy.feature as cfeature
import matplotlib.pyplot as plt
import numpy as np
import xarray as xr
from matplotlib.axes import Axes
from matplotlib.figure import Figure

# Canonical depth dimension name (matches mesh_mask's nav_lev)
DEPTH = "nav_lev"

# Depth dim names used by each grid file
_DEPTH_DIMS = {"deptht", "depthu", "depthv"}


def _assign_xy_coords(ds: xr.Dataset) -> xr.Dataset:
    """Assign integer x/y coords so alignment is always positional."""
    return ds.assign_coords(x=range(ds.sizes["x"]), y=range(ds.sizes["y"]))


def _rename_depth(ds: xr.Dataset) -> xr.Dataset:
    """Rename grid-specific depth dim (deptht/u/v) → DEPTH."""
    for dim in _DEPTH_DIMS & set(ds.dims):
        ds = ds.rename({dim: DEPTH})
    return ds


def load_output(pattern: str, output_dir: str | Path) -> xr.Dataset:
    """Load recombined NEMO output files matching *pattern*.

    Renames the depth dimension to DEPTH and assigns integer x/y coords.
    """
    files = sorted(Path(output_dir).glob(pattern))
    if not files:
        raise FileNotFoundError(
            f"No files matching '{pattern}' in {output_dir}"
        )
    ds = xr.open_mfdataset(files)
    ds = _rename_depth(ds)
    ds = _assign_xy_coords(ds)
    return ds


def load_mesh(output_dir: str | Path) -> xr.Dataset:
    """Load mesh_mask.nc, squeeze out the degenerate time dim.

    Returns a Dataset with integer x/y coords assigned.
    """
    path = Path(output_dir) / "mesh_mask.nc"
    if not path.exists():
        raise FileNotFoundError(f"mesh_mask.nc not found in {output_dir}")
    ds = xr.open_dataset(path, decode_times=False).isel(time_counter=0)
    ds = _assign_xy_coords(ds)
    return ds


def interior_mask(tmask_sfc: xr.DataArray, border: int = 1) -> xr.DataArray:
    """Ocean mask excluding a *border*-cell-wide boundary ring.

    Parameters
    ----------
    tmask_sfc : DataArray
        2-D surface mask (y, x), 1 = ocean, 0 = land.
    border : int
        Number of cells to exclude around the domain edge.
        Use 1 for T-grid quantities, 2 for velocity fields
        (accounts for stagger margin).

    Returns
    -------
    DataArray with 1 inside the interior ocean, 0 elsewhere.
    """
    ny, nx = tmask_sfc.sizes["y"], tmask_sfc.sizes["x"]
    not_boundary = (
        (xr.DataArray(range(ny), dims="y") >= border)
        & (xr.DataArray(range(ny), dims="y") < ny - border)
        & (xr.DataArray(range(nx), dims="x") >= border)
        & (xr.DataArray(range(nx), dims="x") < nx - border)
    )
    return tmask_sfc.where(not_boundary, 0)


def cell_area(mesh: xr.Dataset) -> xr.DataArray:
    """Cell area (m²) from mesh_mask: e1t * e2t."""
    return mesh["e1t"] * mesh["e2t"]


def cell_volume(mesh: xr.Dataset, tmask: xr.DataArray) -> xr.DataArray:
    """Cell volume (m³): cell_area * e3t * tmask.

    Handles the 1-D vertical grid (e3t_1d) used with key_vco_1d.
    *tmask* should have DEPTH as its depth dimension.
    """
    e3t = mesh["e3t_1d"].rename(nav_lev=DEPTH)
    return cell_area(mesh) * e3t * tmask


def grid_angle(mesh: xr.Dataset) -> xr.DataArray:
    """Grid rotation angle (radians): direction of i-axis vs geographic east."""
    glamt = mesh["glamt"]
    gphit = mesh["gphit"]
    dx_lon = glamt.diff("x").pad(x=(0, 1), mode="edge")
    dx_lat = gphit.diff("x").pad(x=(0, 1), mode="edge")
    angle = np.arctan2(dx_lat, dx_lon)
    # Reset x/y to plain integer coords (pad can duplicate index values)
    return angle.assign_coords(x=range(angle.sizes["x"]),
                               y=range(angle.sizes["y"]))


def interp_uv_to_t(
    u: xr.DataArray, v: xr.DataArray,
) -> tuple[xr.DataArray, xr.DataArray]:
    """Interpolate C-grid U/V fields to T-points (simple 2-point average).

    On the Arakawa C-grid, U(i,j) sits at (i+½, j) and V(i,j) at (i, j+½).
    Averaging adjacent values in i (for U) and j (for V) brings both to T(i,j).
    The result has NaN at the domain edges where the shift introduces missing
    neighbours; callers should trim or mask accordingly.
    """
    u_on_t = 0.5 * (u + u.shift(x=-1))
    v_on_t = 0.5 * (v + v.shift(y=-1))
    return u_on_t, v_on_t


def rotate_to_geo(
    ui: xr.DataArray, vj: xr.DataArray, angle: xr.DataArray,
) -> tuple[xr.DataArray, xr.DataArray]:
    """Rotate (i, j)-aligned vectors to geographic (east, north).

    Both *ui* and *vj* must be co-located (same grid point) for the
    rotation to be physically meaningful.  Use :func:`interp_uv_to_t`
    first when working with raw C-grid U/V output.
    """
    u_east = ui * np.cos(angle) - vj * np.sin(angle)
    v_north = ui * np.sin(angle) + vj * np.cos(angle)
    return u_east, v_north


def gyre_map(
    ax: Axes | None = None,
    ds: xr.Dataset | None = None,
    extent: list[float] | None = None,
) -> tuple[Figure, Axes]:
    """Create or configure a Stereographic map axis for the GYRE domain.

    Parameters
    ----------
    ax : matplotlib Axes, optional
        Existing GeoAxes to configure. If None, a new figure is created.
    ds : xarray Dataset, optional
        Dataset with nav_lon/nav_lat to auto-compute extent.
    extent : list of float, optional
        [lon_min, lon_max, lat_min, lat_max]. Overrides ds-derived extent.

    Returns
    -------
    (fig, ax) tuple.
    """
    proj = ccrs.Stereographic(central_longitude=-68, central_latitude=32)
    if ax is None:
        fig, ax = plt.subplots(figsize=(8, 7), subplot_kw=dict(projection=proj))
    else:
        fig = ax.get_figure()

    if extent is None and ds is not None:
        margin = 0.5
        extent = [
            float(ds.nav_lon.min()) - margin,
            float(ds.nav_lon.max()) + margin,
            float(ds.nav_lat.min()) - margin,
            float(ds.nav_lat.max()) + margin,
        ]

    if extent is not None:
        ax.set_extent(extent, crs=ccrs.PlateCarree())

    ax.add_feature(cfeature.LAND, facecolor="tan", edgecolor="k", linewidth=0.5)
    ax.add_feature(cfeature.COASTLINE, linewidth=0.5)
    ax.gridlines(draw_labels=False, alpha=0.3)
    return fig, ax
