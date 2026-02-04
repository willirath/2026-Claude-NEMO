# Building a NEMO GYRE Simulation with Claude Code

A complete record of building a Dockerized NEMO ocean model pipeline —
from `pixi init` to polished analysis notebooks — in conversation with
Claude Code (Opus 4.5). The entire project was developed in a single
sitting across three Claude Code sessions.

---

## Part I: Infrastructure & Simulation

### 1. Project setup

> **User:** Pixi init and add ipykernel, jupyterlab, xarray, numpy,
> matplotlib, netcdf4, cartopy, shapely.

Claude initialized the Pixi environment and added all packages. Committed
as the first project commit.

### 2. Planning

> **User:** I want to run the NEMO ocean model Gyre configuration which
> is defined in the main NEMO repo. Let's plan this out. Plans go to
> plans dir and are written as markdown files.

> **User:** Don't go too far without talking to me.

Claude asked clarifying questions (first time with NEMO? Docker-based?).
The user confirmed Docker as the build environment.

> **User:** We'll probably have to explore the NEMO code a lot. Should we
> have a local copy?

Claude cloned NEMO as a git submodule. Then explored the GYRE config
structure and drafted `plans/nemo-gyre.md` with milestones: Dockerfile,
XIOS build, NEMO build, simulation, output extraction, analysis.

### 3. Dropping the XIOS dependency

> **User:** Defer XIOS until we notice we need it. For small / idealized
> configs, the native output may suffice.

Claude initially (incorrectly) claimed XIOS is a hard dependency. The
user pushed back:

> **User:** I think that's not accurate. Review IO again. There should be
> a way to write \_{T,U,V,W} files without XIOS.

Claude investigated `diawri.F90` and found a complete non-XIOS output
path using **IOIPSL** (bundled in `nemo/ext/IOIPSL/`). This eliminated
the XIOS build step entirely — a significant simplification.

### 4. Docker build

> **User:** Should we track the workflow in a Makefile right away?

Claude created `Dockerfile`, `docker/arch-docker.fcm`, and `Makefile`
with `build`/`run`/`clean` targets.

> **User:** Verify build works.

Three iterations to get the Docker build passing:
1. `makenemo -j12` → needs `-j 4` (space-separated)
2. Missing `liburi-perl` in the container
3. Success — `nemo` executable built

> **User:** Check if (looking forward) we might be running into problems
> with current structure.

Claude identified four issues: no `.dockerignore`, hardcoded x86_64 lib
path (fails on ARM Mac), error-swallowing `|| true` in Makefile, poor
Dockerfile layer ordering. All fixed before moving on.

### 5. Running the simulation

First run crashed with a Fortran format error — Docker container IDs are
too long for NEMO's hostname field. Fixed by setting a short hostname in
the Docker run command.

Second crash: `STOP 123` — two missing PISCES input files.

> **User:** Go for single MPI rank. This is small and shared memory is
> abundant anyway.

The real issue was PISCES namelist defaults requiring external forcing
files. Claude patched `namelist_pisces_cfg` via the Dockerfile to disable
the offending options. Simulation completed: 2-year run producing 10-day
averaged `grid_{T,U,V,W}` NetCDF files.

### 6. Dropping PISCES

> **User:** What's the PISCES part in our simulation? Should we erase it
> completely?

Claude explained that PISCES P2Z was running 9 biogeochemical tracers
with all external forcing disabled — essentially artificial biogeochemistry.

> **User:** Drop it. Also make sure all naming is consistent.

> **User:** RENAME TO GYRE_OCE ... OR just GYRE

Claude removed `key_top`, dropped PISCES namelist patches, renamed
everything from `GYRE_PISCES` to `GYRE`. Full pipeline verified.

### 7. First analysis and README

> **User:** Commit and run a simple analysis. SSH variance plot would be
> enough.

Claude analyzed `sossheig` from `grid_T` output, produced an SSH variance
plot showing the classic double-gyre pattern. Then created a `make all`
pipeline (build → run → analyze), added a README, and pushed to the
GitLab remote.

---

## Part II: Analysis Notebooks

### 8. Reviewing the analysis plan

> **User:** Review the plan and find out if we need to adapt the analysis
> stage.

The plan called for SST, SSH, velocity, and PISCES tracer plots. Only SSH
variance was implemented, and PISCES was no longer applicable.

> **User:** Let's use Jupyter notebooks instead of .py files. Literate
> programming is easier to investigate by humans.

Claude updated the plan with three notebook milestones:
- **3a** `ssh.ipynb` — SSH variance map + domain-mean time series
- **3b** `sst.ipynb` — mean SST, temporal evolution, meridional gradient
- **3c** `circulation.ipynb` — surface current vectors, kinetic energy

### 9. Creating the notebooks

> **User:** Commit updated plan and then act on stage 03.

Claude created all three notebooks, checking NetCDF variables (`sossheig`,
`sosstsst`, `vozocrtx`, `vomecrty`). Updated the Makefile to use
`pixi run jupyter execute --inplace` and removed the old Python script.

> **User:** Where does the executed notebook go? Make sure it's saved in
> place.

Key discovery: `jupyter execute` without `--inplace` does **not** save
cell outputs. Fixed in the Makefile.

### 10. Tuning the plots

> **User:** Look at outputs (esp plots) and tune them. There's a few
> obvious issues.

Claude inspected all plot outputs and found:

| Issue | Cause | Fix |
|---|---|---|
| Black triangles outside grid | Unmasked boundary cells | Applied `tmask` from `mesh_mask.nc` |
| SST boundary ring at 0°C | NEMO boundary cells included | Excluded outermost ring of cells |
| KE plot entirely black | Linear colorscale on sparse data | Switched to `LogNorm` |
| Quiver arrows too dense | Default stride | Increased skip to every 2nd point |
| SSH time series ~ 1e-9 m | `key_linssh` conserves volume | Noted as expected numerical noise |

Important detail: `tmask` in NEMO marks boundary condition cells as
"ocean," so the outermost ring must be manually excluded. For the
staggered velocity grid (Arakawa C-grid), a 2-cell border exclusion is
needed.

### 11. Cartopy maps

> **User:** Put the plots on a regional map with cartopy. Use
> stereographic projection, add 5–10° margin, add coastlines. Don't
> worry that the rect box doesn't fit the coastlines. We *want* to see
> its approx position on the globe and its shape in relation to the real
> Atlantic basin.

Claude added Stereographic projection centered on 68°W, 32°N. The GYRE
domain sits in the western Atlantic — the rotated rectangular grid
overlapping real coastline makes the idealized nature immediately obvious.

> **User:** Smaller margin. (Reduce to 1/2 of current value.)

Reduced from ~8° to ~4°, and later to 0.5° for tight framing with just a
sliver of coastline for context.

### 12. Expanding the analysis suite

> **User:** Add analyses: surface heat flux (zonal mean and map), total
> heat content time series, total KE time series, mean salinity time
> series (should be constant), wind stress quiver. Note the grid dims in
> mesh_mask for the volume integrals.

Claude checked `mesh_mask.nc` for grid metrics:
- `e1t`, `e2t` — horizontal cell dimensions (m)
- `e3t_1d` — vertical layer thicknesses (m)
- Cell volume: `e1t × e2t × e3t × tmask`

Created two new notebooks:

**`heat_salt.ipynb`** — Surface heat flux map (divergent `RdBu_r`
colormap), zonal-mean profile, total heat content
($H = \rho_0 c_p \sum T \cdot \text{vol}$), and volume-mean salinity
(constant at ~35.315 PSU — confirming salt conservation in the closed
basin).

**`forcing_ke.ipynb`** — Wind stress quiver overlaid on stress magnitude,
and total kinetic energy time series ($\text{KE} = \frac{1}{2}\rho_0 \sum
(u^2 + v^2) \cdot \text{vol}$, with U/V interpolated from staggered to
T-grid).

### 13. Fixing vector directions

> **User:** Are you sure about the wind stress and current directions?
> They are in delx, dely direction, I think.

A critical correction. NEMO's `vozocrtx`/`vomecrty` and
`sozotaux`/`sometauy` are along the grid's **i** and **j** axes, not
geographic east and north. The GYRE grid is rotated exactly **45°**.

Claude computed the grid angle from `glamt`/`gphit` and applied a
rotation matrix:

```python
grid_angle = np.arctan2(dx_lat, dx_lon)  # uniformly 45°

def rotate_to_geo(ui, vj, angle):
    cos_a = np.cos(angle)
    sin_a = np.sin(angle)
    u_east  = ui * cos_a - vj * sin_a
    v_north = ui * sin_a + vj * cos_a
    return u_east, v_north
```

After the fix: wind stress correctly shows westerlies in the north and
trades in the south; the western boundary current flows northward.

---

## Part III: Presentation Polish

### 14. Plot styling

> **User:** No grid labels but grid lines OK.

Removed `draw_labels` from cartopy gridlines.

> **User:** Reduce margins to 0.5°.

Final tight framing applied.

### 15. README figure gallery

> **User:** Write the maps from the new analysis notebooks to PNGs and
> add all of them to the README.

Exported 6 map plots (~115–162 KB each) to `figures/` and arranged them
in a 2×3 table:

| | | |
|:---:|:---:|:---:|
| SSH variance | Mean SST | Surface currents |
| Surface KE | Heat flux | Wind stress |

> **User:** Link files from the repo — don't just backtick list them.

All file references made clickable.

> **User:** Make sure font size is balanced for the tabular view.

Bumped matplotlib font sizes (16/18/14 pt) and shortened titles for
readability at thumbnail scale.

> **User:** Click on figure should show raw image at full size. Add a
> link to the notebook under each figure.

Figures now link to the raw PNG; notebook links sit below each image.

### 16. Anchor links — added then reverted

> **User:** Let links behind figures jump to the right section of the
> notebook.

Claude added notebook section anchors (`#ssh-temporal-variance`, etc.).

> **User:** Drop the anchors again. They are not rendering consistently
> between Jupyter Lab, GitLab, and VS Code.

Reverted. A reminder that cross-platform rendering is a real constraint.

---

## Commit history

```
ea7735e Initialize Pixi project with scientific Python dependencies
6f1792c Add NEMO as submodule and write overall project plan
ef12114 Add Dockerfile, arch file, and Makefile for NEMO GYRE build
b8f5fdd Fix Docker build: portable lib paths, .dockerignore, error handling
f7d2e89 Run GYRE_PISCES simulation successfully
22a6aab Add SSH variance analysis from 2-year GYRE_PISCES run
5796ad3 Add make all pipeline: build → run → analyze
7177be7 Add README with setup and usage instructions
8142119 Drop PISCES, rename config to GYRE, fix naming throughout
b1b37e7 Add SSH variance plot to README
9a4ad59 Update plan: Jupyter notebooks for analysis, drop PISCES references
740f804 Replace analysis scripts with Jupyter notebooks
9d07c0e Fix analysis plots: mask boundaries, log-scale KE
87cb9ec Add cartopy maps with stereographic projection and coastlines
3846518 Reduce cartopy map margin from 8 to 4 degrees
28b7839 Add heat/salt budget and wind stress/KE analysis notebooks
25dbc83 Rotate velocity and wind stress vectors from grid to geographic coords
ee525cc Remove grid labels from cartopy maps, keep gridlines
1e01307 Reduce cartopy map margin to 0.5 degrees
5931fcf Add analysis figures to README, remove old ssh_variance.png
8dbcf4a Link files and directories in README instead of backtick listing
ccd6036 Increase font sizes, shorten titles, make figures clickable in README
562ad8e Remove table headers from figure grid in README
a77e093 Add section anchors to README figure links
aad50a5 Remove section anchors from README figure links
90dca9e Link figures to full-size PNGs, add notebook links below each
dd62e37 Gitignore Jupyter checkpoint directories
```

---

## Observations

### What the human caught that the AI didn't

- **XIOS is not required.** Claude initially claimed it was a hard
  dependency. The user knew IOIPSL provides native NetCDF output and
  pushed back. This saved an entire build stage.

- **Vector rotation.** Claude plotted grid-aligned vectors as if they
  were geographic. The user recognized that the GYRE grid is rotated 45°
  and that currents/wind stress must be transformed.

- **Cross-platform anchor rendering.** The user tested on Jupyter Lab,
  GitLab, and VS Code and found inconsistencies that Claude couldn't
  have predicted.

### What the AI handled well

- **Mechanical iteration.** Editing 5 notebooks, re-executing, exporting
  figures, updating the Makefile and README — the kind of work that's
  tedious but must be done carefully.

- **NEMO internals.** Navigating the Fortran source to find IOIPSL
  output paths, identifying the right NetCDF variables, understanding
  `mesh_mask.nc` grid metrics for volume integrals.

- **Debugging cascades.** Docker build failures, Fortran runtime errors,
  missing PISCES files — each required reading logs, tracing the issue,
  and applying a targeted fix.

### The interaction pattern

The session followed a consistent rhythm: the user gave high-level
direction ("add cartopy maps," "fix vector directions"), Claude did the
implementation work, and the user reviewed results and course-corrected.
Domain expertise (oceanography, NEMO specifics) came from the user;
implementation labor (code editing, execution, file management) came from
the AI.

Context limits were hit twice, requiring session continuations. The
earlier build session consumed significant context on NEMO source
exploration — the user noted: "You burn through (unnecessary?) context
fast."
