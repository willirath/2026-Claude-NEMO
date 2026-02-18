# Building a NEMO GYRE Simulation with Claude Code

A complete record of building a Dockerized NEMO ocean model pipeline —
from `pixi init` to polished analysis notebooks to HPC deployment — in
conversation with Claude Code (Opus 4.5/4.6). The project was developed
across multiple sessions spanning three days.

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

## Part IV: Resolution Upgrade

### 17. Increasing to 1/5° resolution

> **User:** Let's increase the spatial resolution to 1/5 deg. Git branch
> first.

Claude created `feature/fifth-degree-resolution` and updated the NEMO
namelist parameters:

| Parameter | 1° | 1/5° | Rationale |
|---|---|---|---|
| `nn_GYRE` | 1 | 5 | Grid: 32×22 → 160×110 |
| `rn_Dt` | 14400 s | 2880 s | CFL scales with grid spacing |
| `nn_itend` | 4320 | 5400 | 6-month run |
| `nn_write` | 60 | 300 | Maintain 10-day output |
| `rn_Ld` | 100 km | 20 km | Scale diffusion with grid |
| `rn_Lv` | 100 km | 20 km | Scale viscosity with grid |

> **User:** Test your work. Might want to go for a really short run first?

Claude ran a 10-step smoke test, then a 5-minute (3000-step) run to
verify the configuration. Both passed cleanly.

### 18. MPI parallelization

> **User:** Can we use OpenMP for shared memory?

Claude investigated the NEMO source and found **zero OpenMP directives**
— NEMO's parallelism is entirely MPI domain decomposition. Adding
`-fopenmp` to compiler flags would have no effect.

> **User:** Try 4 ranks.

Switching from `-np 1` to `-np 4` required:
- Building `rebuild_nemo` (Fortran tool for recombining per-rank NetCDF
  files) in the Dockerfile
- Adding a rebuild step to the Makefile run target
- Installing `ksh` in the container (required by the rebuild wrapper)
- Updating notebook filenames (rebuilt files drop the `_0000` suffix)

A smoke test with 10 steps failed at the rebuild stage — but only
because `nn_write=300` meant zero output records were written. A 300-step
test confirmed the rebuild works when there's actual data.

Timing: **0.039 s/step** with 4 ranks vs **0.10 s/step** single-rank — a
**2.6× speedup**.

### 19. Keeping the submodule read-only

> **User:** Let's figure out how we deal with the fact that we cannot mod
> the nemo/ contents directly.

The namelist had been edited in-place inside the `nemo/` submodule. Claude
moved it to `docker/namelist_cfg` (tracked in the project repo) and added
a `COPY` layer in the Dockerfile to override the submodule's default at
build time. The submodule was reverted to its original state.

### 20. Final pipeline

> **User:** Add savefig calls, subset the quiver, extend run, then
> `make all`.

Changes applied to the analysis notebooks:
- **savefig**: 6 plot cells now write PNGs to `../figures/` automatically
- **Quiver skip**: 2 → 5 (matching the 5× grid refinement)

The full pipeline (`make all`) ran successfully: build, 6-month
simulation at 1/5° with 4 MPI ranks, rebuild, analysis with figure
export. Total wall time under 10 minutes.

Committed on `feature/fifth-degree-resolution`, then fast-forwarded
`main` and deleted the feature branch.

---

## Part V: Configuration Refactoring

### 21. Making configuration discoverable

> **User:** Review if we can improve the repo from the pov of
> configuration / simulation documentation — is it easy to find all the
> details you may want to know about the simulation?

Claude reviewed the repo and identified several discoverability gaps:
compile-time CPP keys were buried in the Dockerfile, namelist files had
cryptic Fortran names without comments, and key decisions (like dropping
PISCES) were hidden in Docker build steps.

> **User:** Where do we, e.g., decide that the bgc component is not
> included?

Claude traced this to a single line in the Dockerfile that overwrites the
CPP keys file — a decision effectively hidden from anyone browsing the
repository.

### 22. Idiomatic NEMO configuration structure

> **User:** Move configs to a more visible central place. There may be
> NEMO idiomatic ways of handling own / adapted configurations. Explore
> those and then let's discuss.

Claude researched NEMO conventions and presented three options:
- **Option A**: Create config inside the `nemo/` submodule directory
- **Option B**: External `configs/` directory using `makenemo -t` flag
- **Option C**: Keep the `docker/` approach with missing files added

Option A was tested but fails because files inside a git submodule cannot
be tracked by the parent repo. The user chose Option B.

Claude created `configs/GYRE_DOCKER/` with CPP keys, namelist, `MY_SRC/`
placeholder for custom Fortran, and a README. This follows the idiomatic
NEMO pattern where external configs reference the source via `makenemo -t`.

### 23. Docker image layout cleanup

The user caught several issues with the Docker filesystem layout:

> **User:** Is it safe to just put stuff into / of the docker image?

Claude had placed configs at `/configs` in the container root. The user
prompted a move to `/opt/nemo-configs`. This cascaded into reorganizing
the entire Docker layout:

| Path | Contents |
|---|---|
| `/opt/nemo-code/` | NEMO source and compiled binaries |
| `/opt/nemo-configs/` | Project configuration (GYRE_DOCKER) |
| `/opt/nemo-run/` | Run directory with symlinks |

The symlinks in `/opt/nemo-run/` point to the executable, namelist_cfg,
and namelist_ref in their actual locations — important foreshadowing for
the Singularity bind-mount issues encountered later.

### 24. Performance experiments

After verifying the refactored build, the user explored CPU behavior:

> **User:** Sure? I saw 800% CPU here at runtime. Check thoroughly.

Claude discovered that Docker's `--cpus 4` is a CPU **quota**, not a
core-pinning flag — the container's 4 MPI ranks were spreading across
all available cores. Added `--cpuset-cpus 0-3` to pin the container to
exactly 4 cores.

Results with 4 ranks:
| Configuration | Time | Change |
|---|---|---|
| No pinning | 205.7s | — |
| Pinned (`--cpuset-cpus 0-3`) | 203.8s | −1% |
| 8 ranks, no pinning | 212.0s | +3% |

The 8-rank run was slightly slower — the domain is too small for that
level of decomposition and halo exchange overhead dominates.

### 25. Native NetCDF output investigation

> **User:** Please, thoroughly investigate (incl. web search) if there is
> no way of writing output natively w/o IOIPSL and w/o XIOS? There could
> just be native NetCDF output?

Claude investigated and concluded: NEMO does not support native NetCDF
for regular diagnostic output. The only options are XIOS or IOIPSL.
Native NetCDF is limited to restart files and state dumps.

---

## Part VI: Analysis Quality

### 26. Notebook audit

> **User:** Let's review the analysis code:
> - ensure NEMO grid is respected for aggregations
> - ensure proper xarray API is used rather than sending around np arrays
> - ensure human readable contents (comments) are exposed w/ markdown
>   cells and in general follow good notebook practices rather than just
>   slapping whole python scripts into 1 or 2 cells.
> Tell me what you find before acting.

Claude read all notebooks and reported three categories of issues:

1. **Grid not respected**: Domain means used flat `.mean()` with no area
   weighting and no land mask. Zonal means in SST used `np.nanmean` with
   no cell-width weighting.

2. **xarray API underused**: All notebooks immediately extracted `.values`
   and operated in numpy-land, discarding coordinate-aware operations.
   Masking used `np.where()` instead of `.where()`.

3. **Notebook practices**: Monolithic cells, minimal markdown
   documentation.

> **User:** Listen for remarks.

Claude jumped ahead and ran diagnostic commands instead of waiting for
the user to finish.

> **User:** Didn't listen?

After apologizing and resetting, the user raised time weighting and
calendar decoding. Claude found that time weights aren't needed (uniform
10-day intervals), but the IOIPSL calendar attribute `360d` breaks
xarray's time decoding because the CF-compliant name is `360_day`.

### 27. Calendar fix

> **User:** Where's a good place to fix the calendar? I don't want this
> repeated in every notebook.

Claude proposed fixing the attribute in the NetCDF files as a
post-processing step in the Makefile. The `360d` string is hardcoded in
NEMO's `domain.F90` (called via IOIPSL when `nn_leapy=30`), so it can't
be changed without patching the submodule.

A one-liner in the Makefile after `rebuild_nemo` patches the `calendar`
attribute from `360d` to `360_day` in all grid output files. Claude also
wrote `analysis/calendar_note.md` referencing CF Conventions Section
4.4.1.

### 28. Notebook rewrite

Claude rewrote all notebooks:
- **Area-weighted means**: `ssh.weighted(cell_area * interior).mean()`
- **xarray API**: `.where()` for masking, `.weighted().mean()` for
  aggregations, `decode_times=True` (now works with the calendar fix)
- **Structure**: Split monolithic cells, added markdown explanations

---

## Part VII: Shared Library & Production Run

### 29. Extracting `analysis/gyre.py`

> **User:** Depth-levels of u, v, t should agree in the Gyre. W doesn't
> (note the vertically staggered grid). There's no x,y dimensional vars
> in NetCDF. This messes w/ xr alignment if we subset. LMK what the lib
> should contain. Then we may discuss details.

Claude designed a shared module with 9 public functions: `load_output`,
`load_mesh`, `interior_mask`, `cell_area`, `cell_volume`, `grid_angle`,
`rotate_to_geo`, `gyre_map`. All five notebooks were refactored to use
it, shrinking each setup cell from ~20–40 lines to ~5–10 lines.

A bug surfaced during execution: `grid_angle` uses `diff().pad()`, and
`pad` duplicated the last x coordinate value, breaking xarray alignment.
Fixed by reassigning clean integer coords.

### 30. Library design corrections

> **User:** Don't hide the output dir in the lib. Really bad pattern.

> **User:** Use type hints in lib.

Claude removed the `OUTPUT_DIR` default, made `output_dir` a mandatory
parameter, and added type hints throughout. All notebooks now define and
pass `OUTPUT_DIR` explicitly.

### 31. One-year production run

> **User:** Let's go for a 1-year run. Adapt namelist, run `make clean`,
> `make all`. No interventions allowed.

Claude set `nn_itend=10800` (360 days × 30 steps/day), ran the full
pipeline, and it completed cleanly — 36 output records, ~408 seconds
wall clock (~7 minutes).

### 32. Configuration comparison

> **User:** There's a 2010 Levy paper defining the GYRE. And there's a
> 2023(±2y) paper by Ekaterina Bagaeva who set up a GYRE with FESOM.
> Read these papers and summarize params of the 20 km resolution configs.

Both papers were behind paywalls. Claude tried multiple access methods
(DOI redirects, ResearchGate, preprint archives, user-agent spoofing) —
all blocked by bot protection. The user eventually provided the Zotero
storage path, and Claude extracted the text with `pdfminer-six`.

The resulting document compared domain size, resolution, forcing,
viscosity, EOS, vertical grid, runtime, and diagnostics across Levy
2010, Bagaeva 2024, and GYRE_DOCKER. Key finding: Levy runs 100 years
(discarding the first 70 as spinup), Bagaeva runs 59 years — both far
longer than the current 1-year run.

> **User:** How long was the 1y run? So what would a 10y run take?

~7 minutes per model year → ~70 minutes for 10 years, ~6 hours for a
50-year spinup.

---

## Part VIII: HPC Deployment

### 33. Planning NESH deployment

> **User:** I'd like to run this big run on an HPC centre. Docs are here:
> https://www.hiperf.rz.uni-kiel.de/nesh/ So we need to turn our Docker
> env container into a Singularity container. Plan this out and test
> building a SIF file and a job script with minimal interaction with me
> (I'm busy otherwise.)

Claude investigated the options. The Docker image was ARM64 (Apple
Silicon) but NESH needs x86_64. Rather than converting locally, the
approach was to cross-build for amd64 via `docker buildx` with QEMU
emulation and push to GitHub Container Registry (GHCR), then pull as a
SIF on NESH.

> **User:** Ah, no if the GH registry works, go for it :D

### 34. Implementation and debugging

Three files were created:
- **Makefile `push` target**: Cross-builds for `linux/amd64` and pushes
  to `ghcr.io/willirath/2026-claude-nemo`, tagged with both `latest` and
  the git short SHA.
- **`hpc/job.sh`**: SLURM job script — copies namelists from the
  container, optionally overrides `nn_itend` via `NEMO_ITEND` env var,
  runs NEMO, rebuilds multi-rank output, symlinks `output/` for notebook
  compatibility.
- **`hpc/README.md`**: Usage instructions for NESH.

The first push failed: `gh auth token` lacked the `write:packages` scope.
Fixed with `gh auth refresh -h github.com -s write:packages`. The
rebuild push took ~11 seconds (cached layers).

### 35. SLURM debugging on NESH

Deploying to NESH required four fix iterations:

| Attempt | Error | Root cause | Fix |
|---|---|---|---|
| 1 | `/var/spool/slurmd/nemo-gyre.sif: no such file` | SLURM copies scripts to spool dir, `dirname $0` resolves wrong | Use `$SLURM_SUBMIT_DIR` |
| 2 | `cp: cannot create regular file` + `/scratch: Read-only file system` | `singularity exec ... cp` runs inside container where host paths aren't mounted; container MPI tried `/scratch` for temp files | Bind `$RUNDIR` for cp steps; set `OMPI_MCA_orte_tmpdir_base=/tmp` |
| 3 | `unable to access or execute: /opt/nemo-run/nemo` | Bind-mounting `$RUNDIR` onto `/opt/nemo-run` hides the `nemo` symlink | Use absolute path to executable: `/opt/nemo-configs/GYRE_DOCKER/EXP00/nemo` |
| 4 | `calendar '360d'` decode error in notebooks | Same IOIPSL calendar issue — the HPC job lacked the fix-up step | Add `pixi run python` calendar patch to `job.sh` |

Additional fixes: host MPI not needed for single-node runs (container
MPI handles shared-memory communication), Singularity cache directed to
repo-local `.singularity_cache/` to avoid `$HOME` quota,
gitignore trailing-slash issue (`output/` doesn't match symlinks, `output`
does).

### 36. First successful HPC run

After the fixes, the 1-year GYRE run completed on NESH. `make analyze`
ran the notebooks against the HPC output via the `output` symlink.

A 10-year run (`NEMO_ITEND=108000`) was submitted.

---

## Observations

(continued from Part IV)

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

- **No OpenMP in NEMO.** The user suggested OpenMP for shared-memory
  parallelism. Claude investigated and correctly reported that NEMO has
  zero `!$omp` directives — but the user had to prompt the
  investigation. The right answer (MPI ranks) was the obvious
  alternative.

- **Submodule hygiene.** Claude initially edited files inside the `nemo/`
  submodule. The user flagged that these changes can't be pushed and
  asked for a clean separation. The solution — a project-local namelist
  copied in at Docker build time — was straightforward once prompted.

- **Quiver density.** At 5× resolution, the original `skip=2` quiver
  stride produced an unreadable arrow field. The user caught this and
  suggested scaling the skip.

- **Area weighting.** Claude's initial notebooks computed domain means
  with flat `.mean()` — no area weighting, no land mask. On NEMO's
  rotated grid with varying cell sizes, this silently biases results.
  The user required proper `weighted()` aggregation.

- **Docker CPU quota vs pinning.** When the user observed 800% CPU,
  Claude initially dismissed it ("already using 4 ranks"). The user
  insisted on a thorough check, and Claude discovered `--cpus` is a
  quota, not a core-pinning flag.

- **Hidden configuration.** The user noticed that key decisions (dropping
  PISCES, CPP keys) were buried in the Dockerfile. This prompted the
  refactoring to an idiomatic `configs/GYRE_DOCKER/` structure.

- **Docker filesystem layout.** Claude put configs at `/configs` in the
  container root. The user asked "is it safe to just put stuff into /?"
  and cascaded into a clean `/opt/` layout.

- **Library API design.** Claude embedded a default `OUTPUT_DIR` in the
  shared library. The user immediately flagged it: "Don't hide the output
  dir in the lib. Really bad pattern."

- **Host MPI not needed.** The plan called for `srun --mpi=pmix` with
  host MPI. The user asked "do we need to bind the host MPI for
  single-node execution?" — the answer was no, simplifying the job
  script significantly.

- **gitignore trailing slash.** `output/` only matches directories, not
  symlinks. The user caught this after the HPC job created a symlink.

### What the AI handled well

- **Mechanical iteration.** Editing 5 notebooks, re-executing, exporting
  figures, updating the Makefile and README — the kind of work that's
  tedious but must be done carefully.

- **NEMO internals.** Navigating the Fortran source to find IOIPSL
  output paths, identifying the right NetCDF variables, understanding
  `mesh_mask.nc` grid metrics for volume integrals.

- **Debugging cascades.** Docker build failures, Fortran runtime errors,
  missing PISCES files, SLURM spool paths, Singularity bind-mount
  overlays — each required reading logs, tracing the issue, and applying
  a targeted fix. The NESH deployment required four fix iterations, each
  diagnosed from the error output.

- **Resolution scaling.** Given `nn_GYRE=5`, Claude correctly derived
  all dependent parameters (timestep, diffusion lengths, output
  frequency, iteration counts) from CFL and physical scaling arguments.

- **Incremental testing.** Smoke-testing with 10 steps before committing
  to long runs caught the rebuild_nemo issue (zero time records) early.
  Timing a 1-month run to estimate full-run cost avoided a blind
  36-minute wait.

- **Build system plumbing.** Compiling `rebuild_nemo` from Fortran
  source, wiring it into the Makefile run target with proper shell
  escaping, and handling the filename suffix change across all notebooks
  — unglamorous but necessary infrastructure work.

- **Cross-platform deployment.** Cross-building the Docker image for
  amd64 via QEMU, pushing to GHCR, creating a SLURM job script with
  proper Singularity bind mounts, and handling the chain of
  container-vs-host filesystem issues — all without access to the target
  cluster.

- **Literature extraction.** When paywalled papers couldn't be fetched
  via web tools, Claude extracted text from a locally stored PDF using
  `pdfminer-six` and synthesized a three-way configuration comparison.

### 37. Interpolate before rotating

> **User:** See the 50y output vorticity.

Before the Bagaeva adaptation work began, Claude fixed a subtle bug in
the vector processing pipeline. On NEMO's Arakawa C-grid, U-velocity
lives on U-points and V-velocity on V-points — they are never
co-located. The `rotate_to_geo()` function was being applied to raw
U/V fields, combining values from different physical locations under a
single rotation matrix.

The correct order of operations: **interpolate to T-points first, then
rotate**. Claude added `interp_uv_to_t()` to `gyre.py`:

```python
def interp_uv_to_t(u, v):
    u_on_t = 0.5 * (u + u.shift(x=-1))  # U-point → T-point
    v_on_t = 0.5 * (v + v.shift(y=-1))  # V-point → T-point
    return u_on_t, v_on_t
```

Updated `circulation.ipynb` and `eddies.ipynb` to call
`interp_uv_to_t()` before `rotate_to_geo()`. Wind stress in
`forcing_ke.ipynb` was left unchanged — IOIPSL writes `sozotaux` and
`sometauy` into the T-grid file without interpolation (a known
limitation of the legacy diagnostics; XIOS handles this correctly).

---

## Part IX: Bagaeva Configuration Adaptation

### 38. Snapshot vorticity

> **User:** See the 50y output vorticity. Let's create a snapshot
> vorticity instead of a mean vorticity?

Claude modified `analysis/vorticity.ipynb` to plot the final time step
instead of the time mean. The two-panel layout (ζ/f and wind stress
curl) was preserved, now with date labels.

### 39. Comparing with Bagaeva et al.

> **User:** Once the results are in, compare our vorticity plot with
> that of Bagaeva et al.

The user provided the PDF from Zotero. Claude extracted Figure 10
(page 21) — snapshots of relative vorticity for the 20 km double-gyre
at various backscatter settings. Claude used `pdftoppm` (installed via
`pixi global install poppler`) to render the page.

Key comparison findings:
- **Vorticity amplitude 4× weaker** — our ζ/f range ±0.035 vs
  Bagaeva's ±0.15, consistent with Laplacian viscosity damping more
  mesoscale energy than biharmonic
- **Less eddy activity** — Bagaeva's baseline shows eddies throughout;
  ours is largely quiescent in the interior
- **Viscosity operator** identified as the dominant difference

### 40. Adapting the configuration

> **User:** Adapt our model config to be as similar as possible to the
> 20km no backscatter Bagaeva config.

Claude dispatched two parallel agents: one to extract exact parameters
from the Bagaeva PDF, the other to audit all NEMO namelist options and
source code for feasibility.

The adaptation plan (`plans/bagaeva_adaptation.md`) identified 8
changes — 5 namelist-only and 3 requiring a source override:

**Namelist changes** (`namelist_cfg`):

| Change | Before | After |
|--------|--------|-------|
| Viscosity | Laplacian, 20 000 m²/s | Biharmonic, 6.67×10¹⁰ m⁴/s |
| EOS | EOS-80 (nonlinear) | Linear S-EOS, T-only |
| Vertical mixing | TKE closure | Pacanowski-Philander |
| Bottom drag | Nonlinear (quadratic) | Linear, Cd = 10⁻³ m/s |
| Run length | 1 year | 59 years (50 spinup + 9 analysis) |

**Source changes** (`MY_SRC/usrdef_sbc.F90`):

| Change | Before | After |
|--------|--------|-------|
| Seasonal cycle | Active (wind, heat, E-P) | Removed (zcos_sais = 0) |
| Heat restoring | −40 W/m²/K | −4 W/m²/K |
| E-P flux | Sinusoidal evap − precip | Zero (constant salinity) |

The biharmonic viscosity coefficient was the hardest to translate:
Bagaeva's FESOM2 uses a flow-aware formulation (Juricke et al. 2020)
with no direct NEMO equivalent. Claude chose constant biharmonic with
`rn_Uv=0.1`, `rn_Lv=20e3` → ahm = 6.67×10¹⁰ m⁴/s, within the
typical range for eddy-permitting models.

Differences kept as-is: vertical levels (31 vs 40), bottom depth
(4300 vs 4000 m), domain geometry, momentum advection scheme —
all either non-trivial to change or fundamental model differences.

### 41. Smoketest

> **User:** I want you to smoketest run the adapted config locally and
> make sure it works before I run on the HPC.

Docker build succeeded (MY_SRC compiled into the binary). A 300-step
run (10 days) completed with exit code 0, producing valid grid files.
Analysis notebooks ran cleanly on the smoketest output.

### 42. Deployment

Docker image pushed to GHCR (`ghcr.io/willirath/2026-claude-nemo:latest`
and `:9da3aa6`). SLURM wall time bumped from 6h to 24h (estimated
runtime ~14 hours for 637200 steps). CLAUDE.md updated with the new
physics configuration and MY_SRC documentation with code diffs.

On NESH:
```
git pull
singularity pull --force nemo-gyre.sif docker://ghcr.io/willirath/2026-claude-nemo:latest
sbatch hpc/job.sh
```

Estimated completion: ~14 hours at ~750 steps/min.

---

## Observations

(continued from Part IV)

### The interaction pattern

The sessions followed a consistent rhythm: the user gave high-level
direction ("add cartopy maps," "fix vector directions," "run this on
NESH"), Claude did the implementation work, and the user reviewed results
and course-corrected. Domain expertise (oceanography, NEMO specifics,
HPC operations) came from the user; implementation labor (code editing,
execution, file management) came from the AI.

The resolution upgrade session showed a tighter feedback loop: the user
steered aggressively on testing strategy ("short run first," "check
timing," "abort — try MPI"), while Claude handled the parameter
arithmetic and build/run mechanics.

The HPC deployment session introduced a new pattern: **remote
debugging**. The user ran commands on NESH and pasted error output back.
Claude diagnosed each failure from the error messages alone and pushed
fixes that the user pulled and tested. Four iterations took the job
script from "nothing works" to a successful run.

A recurring theme was **simplicity over cleverness**. The user repeatedly
steered toward simpler solutions: `make clean` instead of a new test
target, `open_dataset().load()` instead of `open_mfdataset` with dask
workarounds, container MPI instead of host MPI, mandatory parameters
instead of hidden defaults.

Context limits were hit multiple times across the project, requiring
session continuations. The earlier build session consumed significant
context on NEMO source exploration — the user noted: "You burn through
(unnecessary?) context fast."
